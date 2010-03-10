# -*- coding: utf-8 -*-
require 'rubygems'
require 'logger'
require 'sequel'
Sequel::Model.plugin(:schema)
#DB = Sequel.sqlite('/tmp/newgrep.db')
#DB = Sequel.sqlite('/tmp/newgrep.db', :loggers => Logger.new($stdout))
DB = Sequel.mysql 'newgrep', :user => 'nobody', :password => 'nobody', :host => 'localhost', :encoding => 'utf8'#, :loggers => Logger.new($stdout)

def logger
  @Logger ||= Logger.new($stdout)
end

class LineContent < Sequel::Model
  set_schema do
    String :body, :null => false
    foreign_key :document_id
    Fixnum :line
    unique [:document_id, :line]
  end
  create_table unless table_exists?
  many_to_one :document
end

class Document < Sequel::Model
  set_schema do
    primary_key :id
    String :path, :null => false, :uniq => true
    datetime :created_at
    datetime :updated_at
    datetime :indexed_at
  end
  create_table unless table_exists?
  plugin :timestamps, :update_on_create => true
  one_to_many :indices

  def content
    @content ||= open(self.path).read
  end

  def content_at(line)
    LineContent.find(:document_id => self.id, :line => line).body
  end

  def delete_indices
    Index.filter(:document_id => self.id).delete
    LineContent.filter(:document_id => self.id).delete
  end

  def index
    DB.transaction{
      self.delete_indices
      self.content.each_with_index{|line, index|
        line_number = index+1
        LineContent.create(
          :document_id => self.id,
          :body => line,
          :line => line_number
          )
        line.scan(/\w+/).each{|token|
          #logger.debug "TOKEN: #{token}"
          token = Token.find_or_create(:body => token)
          index = Index.create(
            :document_id => self.id,
            :token_id => token.id,
            :line => line_number
            )
        }
      }
      self.indexed_at = Time.now
      self.save
    }
  end

  def should_index
    not self.indexed_at or File.mtime(self.path) > self.indexed_at
  end
end

class Index < Sequel::Model
  set_schema do
    primary_key :id
    foreign_key :document_id, :null => false
    foreign_key :token_id, :null => false
    Fixnum :line, :null => false
  end
  many_to_one :document
  many_to_one :line_content, :key=>[:document_id, :line], :primary_key=>[:document_id, :line]

  create_table unless table_exists?
end

class Token < Sequel::Model
  set_schema do
    primary_key :id
    String :body, :null => false, :uniq => true
  end
  one_to_many :indices, :order => [:document_id, :line], :eager=>[:document, :line_content]
  create_table unless table_exists?
end

def find_document(path)
  Document.find_or_create(:path => File.expand_path(path))
end

def wrap_color(string, keyword, color)
  return string.gsub(keyword, "\e[#{color}m\\&\e[0m")
end

def with_color(string, color)
  return "\e[#{color}m#{string}\e[0m"
end

def search(word, base_path = '/')
  token = Token.find(:body => word)
  token or return token_search(word)
  last_document = nil
  path_filter = Regexp.new('^' + File.expand_path(base_path))
  token.indices.each{|index|
    document = index.document
    next unless document.path =~ path_filter
    puts with_color(document.path, 32) if last_document != document
    last_document = document
    puts "#{index.line}:" + wrap_color(index.line_content.body, word, 43)
  }
end

def token_search(word)
  tokens = Token.filter(:body.like(word + '%'))
  puts "tokens: "
  puts tokens.map(&:body)
end
