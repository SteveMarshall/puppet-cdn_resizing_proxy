# == Class: tizaro/cdn_resizing_proxy
#
# Install and configure a resizing proxy for use behind a CDN.
# === Parameters
#
# [*vhost*]           - Defines the default vHost for the proxy to serve on.
# [*proxy_protocol*]  - Protocol to use to connect to the proxy host.
# [*proxy_host*]      - Proxy server for the root location to connect to.
# [*proxy_port*]      - Port on which to connect to the proxy host.
# [*proxy_base_path*] - Path fragment to prepend to all requests to the
#                       proxy host.
# [*resolver*]        - Domain name servers to use to resolve the
#                       proxy hostname.
class cdn_resizing_proxy (
    $vhost           = undef,
    $proxy_protocol  = undef,
    $proxy_host      = undef,
    $proxy_port      = 80,
    $proxy_base_path = undef,
    $resolver        = '8.8.8.8',
) {
    # Install tizaro-nginx from GitHub as we don't yet have our own apt repo
    include wget
    include apt::update

    $file_name     = 'nginx_1.6.0-1.precise.tizaro_amd64.deb'
    $release_path  = "v1.6.0-1-precise%2Btizaro/${file_name}"
    $releases_root = 'https://github.com/Tizaro/tizaro-nginx/releases/download/'

    $package_path  = "/tmp/${file_name}"
    wget::fetch { "${releases_root}${release_path}":
        destination => $package_path,
    }
    package { 'libmagickwand4':
        require  => Exec['apt_update'],
    }
    package { 'libgd2-xpm':
        require  => Exec['apt_update'],
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
    $resize_simple    = "small_light(${destination_size})"
    $resize_pad       = "small_light(${destination_size}${canvas_size})"

    # Matches /[max-width]x[max-height]/[image_path]
    # Resizes the original image so its sides are within max-width and
    # max-height
    nginx::resource::location { '~* ^/(\d+)x(\d+)/(.+)$':
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
        vhost                => $vhost,
        proxy                => "http://127.0.0.1/\$1x\$2-pad-ffffff/\$3",
    }

    # Matches /[max-width]x[max-height]-pad-[hex-color]/[image_path]
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
        vhost => $vhost,
        proxy => 'http://127.0.0.1/orig/$1',
    }

    # Matches /orig/[image_path]
    # Retrieves the original image from the upstream source
    $proxy_root = "${proxy_protocol}://${proxy_host}:${proxy_port}/"
    nginx::resource::location { '/orig/':
        vhost               => $vhost,
        proxy               => "${proxy_root}${proxy_base_path}",
        location_cfg_append => {
            resolver         => $resolver,
            proxy_set_header => {
                'Host' => $proxy_host,
            },
        }
    }
}

class {'cdn_resizing_proxy':
    vhost           => 'cdn-origin.tizaro.com',
    proxy_protocol  => 'http',
    proxy_host      => 's3-eu-west-1.amazonaws.com',
    proxy_base_path => 'consumed.tizarobot.tizaro.com/',
}
