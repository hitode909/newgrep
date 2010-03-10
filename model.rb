require 'logger'
require 'sequel'
Sequel::Model.plugin(:schema)
#DB = Sequel.sqlite('test.db')
DB = Sequel.sqlite('test.db', :loggers => Logger.new($stdout))

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
    open(self.path).read
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
end

class Index < Sequel::Model
  set_schema do
    primary_key :id
    foreign_key :document_id, :null => false
    foreign_key :token_id, :null => false
    Fixnum :line, :null => false
  end
  create_table unless table_exists?
end

class Token < Sequel::Model
  set_schema do
    primary_key :id
    String :body, :null => false, :uniq => true
  end
  create_table unless table_exists?
end

def document(path)
  Document.find_or_create(:path => File.expand_path(path))
end
