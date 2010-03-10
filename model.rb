require 'termcolor'
require 'logger'
require 'sequel'
Sequel::Model.plugin(:schema)
DB = Sequel.sqlite('test.db')
#DB = Sequel.sqlite('test.db', :loggers => Logger.new($stdout))

# class Line

class Document < Sequel::Model
  set_schema do
    primary_key :id
    String :path, :null => false, :uniq => true
    datetime :created_at
    datetime :updated_at
  end
  create_table unless table_exists?
  plugin :timestamps, :update_on_create => true
  one_to_many :indices

  def content
    @content ||= open(self.path).read
  end

  def content_at(line)
    @lines ||= self.content.split(/\n/)
    @lines[line-1]
  end

  def delete_old_indices
    Index.filter(:document_id => self.id).delete
  end

  def has_token(body, line)
    token = Token.find_or_create(:body => body)
    index = Index.create(
      :document_id => self.id,
      :token_id => token.id,
      :line => line
      )
    index
  end

  def should_reindex
    raise
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
  create_table unless table_exists?
end

class Token < Sequel::Model
  set_schema do
    primary_key :id
    String :body, :null => false, :uniq => true
  end
  one_to_many :indices
  create_table unless table_exists?
end

def find_document(path)
  Document.find_or_create(:path => File.expand_path(path))
end

def wrap_color(string, keyword, color)
  TermColor.parse TermColor.escape(string).gsub(TermColor.escape(keyword),
    "<#{color}>#{TermColor.escape(keyword)}</#{color}>")
end

def with_color(string, color)
  TermColor.parse "<#{color}>#{TermColor.escape(string)}</#{color}>"
end

def search(word)
  token = Token.find(:body => word)
  token or return token_search(word)
  last_document = nil
  token.indices.each{|index|
    document = index.document
    puts with_color(document.path, 32) if last_document != document
    last_document = document
    puts "#{index.line}:" + wrap_color(document.content_at(index.line), word, 43)
  }
end

def token_search(word)
  tokens = Token.filter(:body.like(word + '%'))
  puts "tokens: "
  puts tokens.map(&:body)
end
