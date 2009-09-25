#!/usr/bin/ruby

require 'rubygems'
require 'optparse'

# require my own stuff
require File.expand_path( File.dirname(__FILE__) + "/lib/Comic.rb" )


# parse the commandline options:

options = {}

OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"

  opts.on("-f FILE", "--file FILE", "Specify file to convert") do |file|
    if file.nil? then
      error = "no filename supplied"
      raise StandardError, "please supply a filename as parameter"  
    elsif !File.file?(file) then
      error = "'#{file}' is not a valid file"
      raise StandardError, "'#{file}' is not a valid file"
    else
      options[:file] = file
    end
  end
  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end 
  opts.on("-t TARGET", "--type TARGET", [:indesign, :images, :pdf], "convert to what (indesign, images, pdf)") do |target|
    options[:target] = target
  end

end.parse!

# instantiate a new comic with a comic file from the commandline options
comic = Comic.new( options[:file] )

# generate some output - like an indesign-file or a pdf
comic.generate( options[:target] )

