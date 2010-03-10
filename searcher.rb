require 'logger'
require 'model'

def logger
  @Logger ||= Logger.new($stdout)
end

word = ARGV.first              # XXXXXXXXXXXXX

search(word)
