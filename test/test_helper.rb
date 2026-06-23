# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "stringio"
require "rack"
require "rack/mock"
require "guestbook"
require "minitest/autorun"
