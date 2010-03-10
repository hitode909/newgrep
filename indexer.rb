#!/usr/bin/env ruby
require 'model'

ARGV.each {|filename|
  document = find_document(filename)
  document.index if document and document.should_index
}
