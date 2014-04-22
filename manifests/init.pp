# == Class: tizaro/cdn_resizing_proxy
#
# Install and configure a resizing proxy for use behind a CDN.
# === Parameters
#
# [*vhost*]           - Defines the default vHost for the proxy to serve on.
# [*proxy_host*]      - Proxy server for the root location to connect to.
# [*proxy_port*]      - Port on which to connect to the proxy host.
# [*proxy_protocol*]  - Protocol to use to connect to the proxy host.
# [*proxy_base_path*] - Path fragment to prepend to all requests to the
#                       proxy host.
# [*resolver*]        - Domain name servers to use to resolve the
#                       proxy hostname.
class cdn_resizing_proxy (
    $vhost           = undef,
    $proxy_protocol  = undef,
    $proxy_host      = undef,
    $proxy_port      = 80,
    $resolver        = '8.8.8.8',
    $proxy_base_path = undef,
) {
    class { 'nginx':
        manage_repo => false,
    }

    nginx::resource::vhost { $vhost:
        use_default_location => false,
        index_files          => [],
    }
    nginx::resource::location { '~* ^/info/(.+)$':
        vhost               => $vhost,
        proxy               => 'http://127.0.0.1/$1',
        location_cfg_append => {
            image_filter     => {
                size => ' ',
            },
        }
    }
    nginx::resource::location { '~* ^/([\d\-]+)px/(.+)$':
        vhost               => $vhost,
        proxy               => 'http://127.0.0.1/o/$2',
        location_cfg_append => {
            image_filter        => {
                resize => '$1 $1',
            },
            image_filter_buffer => '5M',
        }
    }
    nginx::resource::location { '~* ^/orig/(.+)$':
        vhost               => $vhost,
        proxy               =>
            "${proxy_protocol}://${proxy_host}:${proxy_port}/\
${proxy_base_path}\$1",
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
