# == Class: SteveMarshall/cdn_resizing_proxy
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
    # If we don't do this, imagetools-nginx dependencies might fail to install
    class { 'apt':
        always_apt_update => true,
    }
    include apt::update

    # Install imagetools-nginx dependencies because dpkg won't do it automatically
    package { 'libmagickwand4':
        require  => Exec['apt_update'],
    }
    package { 'libgd2-xpm':
        require  => Exec['apt_update'],
    }

    # Install imagetools-nginx from GitHub as we don't yet have our own apt repo
    $file_name     = 'nginx_1.6.0-1.precise.imagetools-1_amd64.deb'
    $release_path  = "v1.6.0-1-precise%2Bimagetools-1/${file_name}"
    $releases_root = 'https://github.com/SteveMarshall/imagetools-nginx/releases/download/'
    $package_path  = "/tmp/${file_name}"

    include wget
    wget::fetch { "${releases_root}${release_path}":
        destination => $package_path,
    }
    package { 'nginx-imagetools':
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

    $resize = 'small_light(e=gd,$width,$height,$color)'

    # Matches /[max-width]x[max-height]-max/[image_path]
    # Resizes the original image so its sides are within max-width and
    # max-height
    nginx::resource::location { '~* "^/(-|\d{1,4})x(-|\d{1,4})-max/(.+)$"':
        vhost                => $vhost,
        proxy                => "http://127.0.0.1/${resize}/\${orig}",
        location_cfg_prepend => {
            set => {
                '$width'  => 'dw=$1,',
                '$height' => 'dh=$2,',
                '$orig'   => '$3',
            },
        },
    }

    # Matches /[max-width]x[max-height]-pad/[image_path]
    # Resizes the original image so its sides are within max-width and
    # max-height, and pads the canvas with white to fill those sizes
    nginx::resource::location { '~* "^/(\d{1,4})x(\d{1,4})-pad/(.+)$"':
        vhost               => $vhost,
        location_custom_cfg => {
            rewrite => {
                # HACK: Pass ffffff00 because GD alpha is inverted
                '"^/(\d{1,4})x(\d{1,4})-pad/(.+)$"' => '/$1x$2-pad-ffffff00/$3',
            },
        },
    }

    # Matches /[max-width]x[max-height]-pad-[hex-color]/[image_path]
    # NOTE: hex-color needs inverted alpha because of a bug in small_light+gd
    #       https://github.com/cubicdaiya/ngx_small_light/issues/9
    # Resizes the original image so its sides are within max-width and
    # max-height, and pads the canvas with [hex-color] to fill those sizes
    nginx::resource::location { '~* "^/(\d{1,4})x(\d{1,4})-pad-([0-9a-f]{3,8})/(.+)$"':
        vhost                => $vhost,
        proxy                => "http://127.0.0.1/${resize}/\${orig}",
        location_cfg_prepend => {
            set => {
                '$width'  => 'dw=$1,cw=$1',
                '$height' => 'dh=$2,ch=$2',
                '$color'  => 'cc=$3',
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
