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

    $package_url = 'https://github.com/Tizaro/tizaro-nginx/releases/download/v1.6.0-1-precise%2Btizaro/nginx_1.6.0-1.precise.tizaro_amd64.deb'
    $package_path = '/tmp/nginx_1.6.0-1.precise.tizaro_amd64.deb'
    wget::fetch { $package_url:
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
        ensure => absent,
        require => Package['nginx'],
        notify => Service['nginx'],
    }
    file { '/etc/nginx/conf.d/example_ssl.conf':
        ensure => absent,
        require => Package['nginx'],
        notify => Service['nginx'],
    }

    class { 'nginx':
        manage_repo => false,
    }

    nginx::resource::vhost { $vhost:
        use_default_location => false,
        index_files          => [],
    }
    # Matches /info/[image_path]
    # Returns a JSON response with image information (height/width/type)
    # for the proxied URL (one of the other locations below)
    nginx::resource::location { '~* ^/info/(.+)$':
        vhost               => $vhost,
        proxy               => 'http://127.0.0.1/$1',
        location_cfg_append => {
            image_filter     => {
                size => ' ',
            },
        }
    }
    # Matches /[size]px/[image_path]
    # Resizes the original image so its longest side is $1px
    # This will fail if the original image is larger than 5M
    nginx::resource::location { '~* ^/(\d+)px/(.+)$':
        vhost               => $vhost,
        proxy               => 'http://127.0.0.1/orig/$2',
        location_cfg_append => {
            image_filter        => {
                resize => '$1 $1',
            },
            image_filter_buffer => '5M',
        }
    }
    # Matches /orig/[image_path]
    # Retrieves the original image from the upstream source
    $proxy_root = "${proxy_protocol}://${proxy_host}:${proxy_port}/"
    nginx::resource::location { '~* ^/orig/(.+)$':
        vhost               => $vhost,
        proxy               => "${proxy_root}${proxy_base_path}\$1",
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
