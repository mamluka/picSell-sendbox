require 'rubygems'
require 'httparty'
require 'base64'
require 'cgi'
require 'openssl'
# require 'hashie/mash'
require 'hashie'
require 'rash'

module MWS
  def self.new(options={})
    MWS::Base.new(options.symbolize_keys!)
  end
end

# Some convenience methods randomly put here. Thanks, Rails

class Hash
  def stringify_keys!
    keys.each do |key|
      self[key.to_s] = delete(key)
    end
    self
  end

  def symbolize_keys!
    self.replace(self.symbolize_keys)
  end

  def symbolize_keys
    inject({}) do |options, (key, value)|
      options[(key.to_sym rescue key) || key] = value
      options
    end
  end
end

class String

  def camelize(first_letter_in_uppercase = true)
    if first_letter_in_uppercase
      self.to_s.gsub(/\/(.?)/) { "::#{$1.upcase}" }.gsub(/(?:^|_)(.)/) { $1.upcase }
    else
      self.to_s[0].chr.downcase + camelize(lower_case_and_underscored_word)[1..-1]
    end
  end
end

require_relative 'ruby-mws/base'
require_relative 'ruby-mws/connection'
require_relative 'ruby-mws/exceptions'
require_relative 'ruby-mws/version'

require_relative 'ruby-mws/api/base'
require_relative 'ruby-mws/api/inventory'
require_relative 'ruby-mws/api/order'
require_relative 'ruby-mws/api/products'
require_relative 'ruby-mws/api/query'
require_relative 'ruby-mws/api/response'