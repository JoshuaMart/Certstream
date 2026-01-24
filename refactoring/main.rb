#!/usr/bin/env ruby
# frozen_string_literal: true

$stdout.sync = true
$stderr.sync = true

require_relative 'lib/certstream'

Certstream::CLI.start(ARGV)
