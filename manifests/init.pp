# == Class: tizaro/cdn_resizing_proxy
#
# Install and configure a resizing proxy for use behind a CDN.
# === Parameters
#
# [*vhost*]           - Defines the default vHost for the proxy to serve on.
# [*proxy_protocol*]  - Protocol to use to connect to the proxy host.
# [*proxy_host*]      - Proxy server for the root location to connect to.
# [*proxy_base_path*] - Path fragment to prepend to all requests to the
#                       proxy host.
# [*resolver*]        - Domain name servers to use to resolve the
#                       proxy hostname.
# [*expires*]         - Cache control and resource expiration, per the
#                       nginx documentation:
#            http://nginx.org/en/docs/http/ngx_http_headers_module.html#expires
class cdn_resizing_proxy (
    $vhost           = undef,
    $proxy_protocol  = undef,
    $proxy_host      = undef,
    $proxy_base_path = undef,
    $resolver        = '8.8.8.8',
    $expires         = 'max'
) {
    # Ensure apt-get update actually runs when we `require` it
    # If we don't do this, tizaro-nginx dependencies might fail to install
    class { 'apt':
        always_apt_update => true,
    }
    include apt::update

    # Install tizaro-nginx dependencies because dpkg won't do it automatically
    package { 'libmagickwand4':
        require  => Exec['apt_update'],
    }
    package { 'libgd2-xpm':
        require  => Exec['apt_update'],
    }

    # Install tizaro-nginx from GitHub as we don't yet have our own apt repo
    $file_name     = 'nginx_1.6.0-1.precise.tizaro-1_amd64.deb'
    $release_path  = "v1.6.0-1-precise%2Btizaro-1/${file_name}"
    $releases_root = 'https://github.com/Tizaro/tizaro-nginx/releases/download/'
    $package_path  = "/tmp/${file_name}"

    include wget
    wget::fetch { "${releases_root}${release_path}":
        destination => $package_path,
    }
    package { 'nginx-tizaro':
        provider => 'dpkg',
        source   => $package_path,
        require  => [Package['libmagickwand4'], Package['libgd2-xpm']],
    }

    file { '/etc/nginx/conf.d/default.conf':
        ensure  => absent,
        require => Package['nginx'],
        notify  => Service['nginx'],
    }
    file { '/etc/nginx/conf.d/example_ssl.conf':
        ensure  => absent,
        require => Package['nginx'],
        notify  => Service['nginx'],
    }

    class { 'nginx':
        manage_repo => false,
    }

    nginx::resource::vhost { $vhost:
        use_default_location => false,
        index_files          => [],
        vhost_cfg_prepend    => {
            small_light => 'on',
            expires     => $expires,
            resolver    => $resolver,
        },
    }

    # Matches /info/[image_path]
    # Returns a JSON response with image information (height/width/type)
    # for the proxied URL (one of the other locations below)
    nginx::resource::location { '/info/':
        vhost               => $vhost,
        proxy               => 'http://127.0.0.1/',
        location_cfg_append => {
            image_filter => {
                size => ' ',
            },
        },
    }

    $destination_size = "dw=\${width},dh=\${height},"
    $canvas_size      = "cw=\${width},ch=\${height},cc=\${color}"
    $resize_simple    = "small_light(e=gd,${destination_size})"
    $resize_pad       = "small_light(e=gd,${destination_size}${canvas_size})"

    # Matches /[max-width]x[max-height]-max/[image_path]
    # Resizes the original image so its sides are within max-width and
    # max-height
    nginx::resource::location { '~* ^/(\d+)x(\d+)-max/(.+)$':
        vhost                => $vhost,
        proxy                => "http://127.0.0.1/${resize_simple}/\${orig}",
        location_cfg_prepend => {
            set => {
                '$width'  => '$1',
                '$height' => '$2',
                '$orig'   => '$3',
            },
        },
    }

    # Matches /[max-width]x[max-height]-pad/[image_path]
    # Resizes the original image so its sides are within max-width and
    # max-height, and pads the canvas with white to fill those sizes
    nginx::resource::location { '~* ^/(\d+)x(\d+)-pad/(.+)$':
        vhost               => $vhost,
        location_custom_cfg => {
            rewrite => {
                # HACK: Pass ffffff00 because GD alpha is inverted
                '^/(\d+)x(\d+)-pad/(.+)$' => '/$1x$2-pad-ffffff00/$3',
            },
        },
    }

    # Matches /[max-width]x[max-height]-pad-[hex-color]/[image_path]
    # NOTE: hex-color needs inverted alpha because of a bug in small_light+gd
    #       https://github.com/cubicdaiya/ngx_small_light/issues/9
    # Resizes the original image so its sides are within max-width and
    # max-height, and pads the canvas with [hex-color] to fill those sizes
    nginx::resource::location { '~* ^/(\d+)x(\d+)-pad-([0-9a-f]+)/(.+)$':
        vhost                => $vhost,
        proxy                => "http://127.0.0.1/${resize_pad}/\${orig}",
        location_cfg_prepend => {
            set => {
                '$width'  => '$1',
                '$height' => '$2',
                '$color'  => '$3',
                '$orig'   => '$4',
            },
        },
    }

    # Matches /small_light[params]/[image_path]
    # Required format for ngx_small_light image processing
    # Supported params are documented at
    # https://github.com/cubicdaiya/ngx_small_light/wiki/Configuration
    nginx::resource::location { '~ ^/small_light[^/]*/(.+)$':
        vhost               => $vhost,
        location_custom_cfg => {
            rewrite => {
                '^/small_light[^/]*/(.+)$' => '/$1',
            },
        }
    }

    # Matches /product/[tizaro-sku]_[image-number][extension]
    # Can be used with all resizers/small_light
    $sku   = '([A-Z0-9]{3})([A-Z0-9]{3})([A-Z0-9]{2})'
    $image = '(\d+)'
    $type  = '([^$]+)'
    $sku_image_path = '$1/$2/$3/'
    $sku_image_name = '$1$2$3_$4$5'
    $sku_image_fullpath = "/images/${sku_image_path}${sku_image_name}"
    nginx::resource::location { "~* \"^/product/${sku}_${image}${type}$\"":
        vhost               => $vhost,
        location_custom_cfg => {
            rewrite => {
                "'^/product/${sku}_${image}${type}$'"
                => "'${sku_image_fullpath}'",
            },
        },
    }

    # Matches /[path]
    # Retrieves the original file from the upstream source
    $proxy_root = "${proxy_protocol}://${proxy_host}/"
    nginx::resource::location { '/':
        vhost               => $vhost,
        proxy               => "${proxy_root}${proxy_base_path}",
        location_cfg_append => {
            proxy_set_header => {
                'Host' => $proxy_host,
            },
        }
    }
}

class {'cdn_resizing_proxy':
    vhost           => 'resizer.cdn.tizaro.com',
    proxy_protocol  => 'https',
    proxy_host      => 's3-eu-west-1.amazonaws.com',
    proxy_base_path => 'origin-1.cdn.tizaro.com/',
}
