#!/usr/bin/env ruby

$:.unshift(File.dirname(__FILE__)) unless $:.include?(File.dirname(__FILE__)) ||
                                          $:.include?(File.expand_path(File.dirname(__FILE__)))
require 'model'

ARGV.each {|filename|
  begin
    puts "indexing #{filename}"
    document = find_document(filename)
    document.index if document and document.should_index
  rescue => e
    puts e
  end
}
