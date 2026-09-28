# frozen_string_literal: true

module AdsCrawl
  # Public so custom transports can return a response without depending on internals.
  HttpResponse = Struct.new(:status, :headers, :body, keyword_init: true)
end
