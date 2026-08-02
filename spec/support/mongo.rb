require 'mongo'

module Spec

  # MongoDBAdapter memoizes one client process-wide, so its integration specs
  # must use the same server and database.
  MONGODB_DATABASE = 'steam_test'
  MONGODB_HOSTS    = ['127.0.0.1:27017'].freeze

end

Mongo::Logger.logger.level = Logger::INFO
# Mongo::Logger.logger       = Logger.new($stdout)
# Mongo::Logger.logger.level = Logger::DEBUG
