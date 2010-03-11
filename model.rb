# -*- coding: utf-8 -*-
require 'rubygems'
require 'logger'
require 'sequel'
Sequel::Model.plugin(:schema)
#DB = Sequel.sqlite('/tmp/newgrep.db')
#DB = Sequel.sqlite('/tmp/newgrep.db', :loggers => Logger.new($stdout))
DB = Sequel.mysql 'newgrep', :user => 'nobody', :password => 'nobody', :host => 'localhost', :encoding => 'utf8'#, :loggers => Logger.new($stdout)

USE_COLOR = $stdout.tty?

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

class Directory < Sequel::Model
  set_schema do
    primary_key :id
    String :path, :null => false, :uniq => true
  end
  create_table unless table_exists?
  one_to_many :indices

  def self.neighbors(basedir)
    basedir = File.expand_path(basedir)
    directories = self.filter(:path.like(basedir + '%')).all
  end
end

class Document < Sequel::Model
  set_schema do
    primary_key :id
    String :path, :null => false, :uniq => true
    foreign_key :directory_id
    datetime :created_at
    datetime :updated_at
    datetime :indexed_at
  end
  create_table unless table_exists?
  plugin :timestamps, :update_on_create => true
  one_to_many :indices

  def before_create
    directory = Directory.find_or_create(:path => File.dirname(self.path))
    self.directory_id = directory.id
  end

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
      position = 0
      self.content.each_with_index{|line, index|
        line_number = index+1
        LineContent.create(
          :document_id => self.id,
          :body => line.chomp,
          :line => line_number
          )
        first_position = position
        last_token = nil
        Token.tokenize(line).each{|token|
          position = first_position if last_token and token.length < last_token.length
          Index.create(
            :document_id => self.id,
            :directory_id => self.directory_id,
            :token_id => token.id,
            :line => line_number,
            :position => position
            )
          position += 1
          last_token = token
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
    foreign_key :directory_id, :null => false
    foreign_key :token_id, :null => false
    Fixnum :line, :null => false
    Fixnum :position, :null => false
  end
  many_to_one :document
  many_to_one :directory
  many_to_one :token
  many_to_one :token
  many_to_one :line_content, :key=>[:document_id, :line], :primary_key=>[:document_id, :line]

  create_table unless table_exists?
end

class Token < Sequel::Model
  set_schema do
    primary_key :id
    varbinary :body, :null => false, :uniq => true, :size=> 16
    Fixnum :length, :null => false
  end
  create_table unless table_exists?
  one_to_many :indices

  # returns array of token
  def self.tokenize(line)
    DB.transaction {
      (0..(line.length-3)).map{ |i|
        self.find_or_create(:body => line[i, 3].rstrip, :length => 3)
      }
    }
  end
end

def find_document(path)
  Document.find_or_create(:path => File.expand_path(path))
end

def wrap_color(string, keyword, color)
  if USE_COLOR
    string.gsub(keyword, "\e[#{color}m\\&\e[0m")
  else
    string
  end
end

def with_color(string, color)
  if USE_COLOR
    "\e[#{color}m#{string}\e[0m"
  else
    string
  end
end

def search(word, base_path = '/')
  tokens = Token.tokenize(word)
  last_document = nil
  last_line = nil
  dirs = Directory.neighbors(File.expand_path(base_path))
  indices = Index.filter(:token_id => tokens.map(&:id), :directory_id => dirs.map(&:id)).order(:document_id, :position).eager(:token, :document, :line_content).all

  while indices.length >= tokens.length
    slice = indices[0, tokens.length]
    if slice.map(&:token) == tokens and slice[1..-1].inject(slice.first){ |a, b| a and a.position + 1 == b.position ? b : false }
      indices.shift(tokens.length)
      index = slice.first
      document = index.document
      last_line = nil if last_document and last_document != document
      next if last_line and last_line == index.line
      last_line = index.line
      puts if last_document and last_document != document
      puts with_color(document.path, 32) if last_document != document
      last_document = document
      puts "#{index.line}:" + wrap_color(index.line_content.body, word, 43)
    else
      indices.shift
    end
  end
end
