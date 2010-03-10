require 'logger'
require 'model'

def logger
  @Logger ||= Logger.new($stdout)
end

ARGV.each {|filename|
  document = find_document(filename)
  if document.should_index
    document.delete_old_indices
    document.index
  end
}
