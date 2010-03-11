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
    varbinary :body, :null => false, :uniq => true, :size=> 4
    Fixnum :length, :null => false
  end
  create_table unless table_exists?
  one_to_many :indices

  def used_count
    @used_count ||= self.indices.count
  end

  # returns array of token
  def self.tokenize(line)
    DB.transaction {
      (0..(line.length-3)).map{ |i|
        self.find_or_create(:body => line[i, 3].rstrip, :length => 3)
      } +
      (0..(line.length-2)).map{ |i|
        self.find_or_create(:body => line[i, 2].rstrip, :length => 2)
      }
    }
  end

  # returns array of token
  # body.length is 2 or 3
  def self.slice(line)
    case line.length % 3
    when 0
      diffs = Array.new(line.length / 3, 3)
    when 1
      diffs = Array.new(line.length / 3 - 1,3).concat([2, 2])
    when 2
      diffs = Array.new(line.length / 3,3).concat([2])
    end
    DB.transaction {
      sum = 0
      diffs.map{|i|
        token = self.find_or_create(:body => line[sum, i].rstrip, :length => i)
        sum += i
        token
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

def slice_each(list, len, &block)
  (0..(list.length - len)).map{ |i|
    yield(list[i, len])
  }
end

def search(word, base_path = '/')
  tokens = Token.slice(word)
  token_ids = tokens.map(&:id)
  last_document = nil
  dirs = Directory.neighbors(File.expand_path(base_path))
  indices = Index.filter(:token_id => tokens.map(&:id), :directory_id => dirs.map(&:id)).order(:document_id, :position).eager(:token, :document, :line_content).all
  skip_count = 0
  slice_each(indices, tokens.length){ |slice|
    if skip_count > 0
      skip_count -= 1
      next
    end
    if slice.map{|i| i.token.id} == token_ids and slice[1..-1].inject(slice.first){ |r, i| r and r.position + 3 >= i.position ? i : nil }
      index = slice.first
      document = index.document
      puts if last_document and last_document != document
      puts with_color(document.path, 32) if last_document != document
      last_document = document
      puts "#{index.line}:" + wrap_color(index.line_content.body, word, 43)
      skip_count += tokens.length - 1
    end
  }
end
