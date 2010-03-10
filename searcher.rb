#!/usr/bin/env ruby

$:.unshift(File.dirname(__FILE__)) unless $:.include?(File.dirname(__FILE__)) ||
  $:.include?(File.expand_path(File.dirname(__FILE__)))
require 'model'

search(ARGV.first, Dir.pwd)
