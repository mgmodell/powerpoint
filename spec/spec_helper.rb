require 'coveralls'

Coveralls.wear! do
  add_filter '/spec/'
  minimum_coverage 90
end

require 'powerpoint'
require 'tmpdir'
require 'fileutils'
require 'zip'
