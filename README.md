tizaro-cdn_resizing_proxy
=========================

Puppet module to install and configure a resizing proxy for use behind a CDN.

Usage
-----

TBD

Development
-----------

This project requires [Vagrant
1.5](http://www.vagrantup.com/downloads.html) with the
[`vagrant-librarian-puppet`
plugin](https://github.com/mhahn/vagrant-librarian-puppet) (which can
be installed by running
`vagrant plugin install vagrant-librarian-puppet`).

You will also want to run `bundle install` (assumming you have
[Bundler](http://bundler.io) already) to install some of the
development dependencies (notably, Puppet, to allow librarian-puppet to
run). To lint the puppet module, run `rake lint` (because using
`puppet-lint` directly offers no way to ignore directories. Ug.)
