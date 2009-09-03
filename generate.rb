#!/usr/bin/ruby

require 'rubygems'
require 'optparse'
require 'hpricot'
require 'appscript'
include Appscript

# define comic structure

class Comic
  
  attr_accessor :defaults, :pages
  
  # initializer: parse comic-xml-file into local structure
  def initialize( file )
    @defaults = Hash.new
    @pages = Array.new
    
    hpricotfile = Hpricot(open(file))
    
    # parse comic-defaults (page size, margins...)
    hpricotfile.search("defaults").each do |defaults|
      defaults.attributes.each do |key, value|
        @defaults[key.to_sym] = value
      end
    end
    
    # parse the content of each page: panels with speech-bubbles and such
    hpricotfile.search("page").each do |page|
      currentPage = Page.new
      currentPage.attributes[:description] = page.at("description").inner_html.strip
      currentPage.attributes[:id] = page.attributes.fetch("id").to_i
      page.search("panel").each do |panel|
        currentPanel = Panel.new
        currentPanel.attributes[:description] = panel.at("description").inner_html.strip
        panel.attributes.each do |key, value|
          currentPanel.attributes[key.to_sym] = value
        end
        panel.search("text").each do |text|
          currentText = Hash.new
          currentText[:content] = text.inner_html.strip
          text.attributes.each do |key, value|
            currentText[key.to_sym] = value
          end
          currentPanel.text << currentText
        end
        currentPage.panels << currentPanel
      end
      @pages << currentPage
    end
  end
  
  def generate(target)
    if target == :indesign then
      
      puts "hallo indesign!"
      indesign = app("Adobe InDesign CS3")
      
      indesign.view_preferences.set(app.view_preferences.horizontal_measurement_units, :to => :millimeters)
      indesign.view_preferences.set(app.view_preferences.vertical_measurement_units, :to => :millimeters)
      indesign.margin_preferences.set(app.margin_preferences.top, :to => @defaults[:kopfsteg] )
      indesign.margin_preferences.set(app.margin_preferences.bottom, :to => @defaults[:fusssteg] )
      indesign.margin_preferences.set(app.margin_preferences.left, :to => @defaults[:bundsteg] )
      indesign.margin_preferences.set(app.margin_preferences.right, :to => @defaults[:aussensteg] )
      doc = indesign.make(:new => :document, :with_properties => {
          :document_preferences => {
                                       
                                       :pages_per_document => 10,
                                       :facing_pages => true,
                                       :document_slug_uniform_size => false,
                                       :document_bleed_uniform_size => false,
                                       :page_width => @defaults[:pagewidth],
                                       :page_height => @defaults[:pageheight],
                                       :margin_guide_color => "gray",
                                       :column_guide_color => "gray",
                                   },                      
      })
      doc.pages[1].make(:new => :rectangle, :with_properties => {
          :geometric_bounds => [30, 10, 60, 60]
      })
      
    elsif target == :images then
      puts "target images: not yet implemented"
    elsif target == :pdf then
      puts "target pdf: not yet implemented"
    end
    
  end
  
end

class Page

  attr_accessor :attributes, :panels

  def initialize
    @attributes = Hash.new
    @panels = Array.new
  end
end  

class Panel
  
  attr_accessor :attributes, :text
  
  def initialize
    @attributes = Hash.new
    @text = Array.new
  end
end  


# first, parse the commandline options:

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


comic = Comic.new( options[:file] )
comic.generate( options[:target] )

