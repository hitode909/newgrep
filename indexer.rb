require 'logger'
require 'model'

def logger
  @Logger ||= Logger.new($stdout)
end

ARGV.each {|filename|
  doc = document(filename)
  doc.delete_old_indices
  doc.content.each_with_index{|line, index|
    line.scan(/\w+/).each{|token|
      logger.debug "TOKEN: #{token}"
      doc.has_token(token, index)
    }
  }
}






