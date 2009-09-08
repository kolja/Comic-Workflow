#!/usr/bin/ruby

require 'rubygems'
require 'yaml'
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
        unit = value.slice!(/\D*$/) # strip unit – and ignore it for now.
        @defaults[key.to_sym] = value.to_f
      end
      @defaults[:content_width] = @defaults[:pagewidth] - @defaults[:aussensteg] - @defaults[:bundsteg]
      @defaults[:content_height] = @defaults[:pageheight] - @defaults[:kopfsteg] - @defaults[:fusssteg]
      @defaults[:panel_width] = @defaults[:content_width] / @defaults[:panelsperrow]
      @defaults[:panel_height] = @defaults[:content_height] / @defaults[:panelspercol]
    end
    
    # parse the content of each page: panels with speech-bubbles and such
    hpricotfile.search("page").each do |page|
      currentPage = Page.new
      currentPage.parent = self
      if page.at("description") then currentPage.attributes[:description] = page.at("description").inner_html.strip end
      currentPage.attributes[:id] = page.attributes.fetch("id").to_i

      page.search("panel").each do |panel|
        currentPanel = Panel.new(currentPage)
        if panel.at("description") then currentPanel.attributes[:description] = panel.at("description").inner_html.strip end
        panel.attributes.each do |key, value|
          currentPanel.attributes[key.to_sym] = value
        end
        # set panel float behaviour
        if currentPanel.attributes.has_key?(:float) then
          if currentPanel.attributes[:float] == "true" then
            currentPanel.attributes[:float] = true
          else
            currentPanel.attributes[:float] = false
          end
        else
          currentPanel.attributes[:float] = true
        end
        # set panel width
        if currentPanel.attributes.has_key?(:width) then
          unit = currentPanel.attributes[:width].slice!(/\D*$/)
          if unit == "x" then
            currentPanel.attributes[:width] = currentPanel.attributes[:width].to_f * @defaults[:panel_width]
          elsif unit == "max" then
            currentPanel.attributes[:width] = 0 # deal with this case later
          else
            currentPanel.attributes[:width] = currentPanel.attributes[:width].to_f
          end
        else
          currentPanel.attributes[:width] = @defaults[:panel_width]
        end
        # ...and height
        if currentPanel.attributes.has_key?(:height) then
          unit = currentPanel.attributes[:height].slice!(/\D*$/)
          if unit == "x" then
            currentPanel.attributes[:height] = currentPanel.attributes[:height].to_f * @defaults[:panel_height]
          elsif unit == "max" then
            currentPanel.attributes[:height] = 0 # deal with this case later
          else
            currentPanel.attributes[:height] = currentPanel.attributes[:height].to_f
          end
        else
          currentPanel.attributes[:height] = @defaults[:panel_height]
        end
        # ---
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
      @pages << currentPage.arrange!
    end
  end
  
  def generate(target)
    if target == :indesign then
      
      puts "hallo indesign!"
      indesign = app("Adobe InDesign CS3")
      indesign.view_preferences.ruler_origin.set(:page_origin)
      indesign.view_preferences.set(app.view_preferences.horizontal_measurement_units, :to => :millimeters)
      indesign.view_preferences.set(app.view_preferences.vertical_measurement_units, :to => :millimeters)
      indesign.margin_preferences.set(app.margin_preferences.top, :to => @defaults[:kopfsteg] )
      indesign.margin_preferences.set(app.margin_preferences.bottom, :to => @defaults[:fusssteg] )
      indesign.margin_preferences.set(app.margin_preferences.left, :to => @defaults[:bundsteg] )
      indesign.margin_preferences.set(app.margin_preferences.right, :to => @defaults[:aussensteg] )
      doc = indesign.make(:new => :document, :with_properties => {
          :document_preferences => {                                 
                                       :pages_per_document => pages.size,
                                       :facing_pages => true,
                                       :page_width => @defaults[:pagewidth],
                                       :page_height => @defaults[:pageheight],
                                   },                      
      })
      
      div2 = @defaults[:dividerwidth] / 2
      pages.each do |p|
        p.panels.each do |panel|
          doc.pages[p.attributes[:id]].make(:new => :rectangle, :with_properties => { :geometric_bounds => [
                                                                            panel.origin.y + div2, 
                                                                            panel.origin.x + div2, 
                                                                            panel.origin.y + panel.size.y - div2, 
                                                                            panel.origin.x + panel.size.x - div2  ] 
                                                                      } )
        end
      end
      
    elsif target == :images then
      puts "target images: not yet implemented"
    elsif target == :pdf then
      puts "target pdf: not yet implemented"
    end
    
  end
  
end

# Page represents a page in a comic-book. It has lots of panels
class Page

  attr_accessor :attributes, :panels, :parent

  def initialize
    @attributes = Hash.new
    @panels = Array.new
  end
  
  def arrange!
    panels.each do |panel| panel.arrange! end
    return self
  end

  def margin_left # on even pages, the left margin is the 'outer' margin
    if self.even? then
      parent.defaults[:aussensteg]
    else
      parent.defaults[:bundsteg]
    end 
  end

  def margin_top
    parent.defaults[:kopfsteg]
  end

  def margin_right # on even pages, the right margin is the 'inner' margin
    if self.even? then
      parent.defaults[:bundsteg]
    else
      parent.defaults[:aussensteg]
    end
  end

  def margin_bottom
    parent.defaults[:fusssteg]
  end

  def even?
    if attributes[:id].to_i % 2 == 0 then
      true
    else
      false
    end
  end

  def include?(point)
    point.x >= self.margin_left && point.x <= self.margin_right && point.y >= self.margin_top && point.y <= self.margin_bottom
  end
  
end  

# A Panel represents a single Panel on the page of a comic book.
# the page should call its "arrange" method do position it somewhere.
class Panel
  
  attr_accessor :attributes, :parentpage, :text, :size, :origin
  
  def initialize( parent )
    @attributes = Hash.new
    @parentpage = parent # the page that this panel belongs to
    @text = Array.new
    @size = Point.new
    @origin = Point.new
  end
  
  def arrange!
    if self == parentpage.panels.first then # we are dealing with the first panel on a page here
      origin.x = parentpage.margin_left
      origin.y = parentpage.margin_top
    elsif self.float? then
      self.float_h( self.previous ) # position a panel on the right side of it's predecessor
    else # panel not floating
      self.float_v( self.previous ) # position a panel below its predecessor
    end   
    self.setSize!
  end
  
  def float? # by default, panels float (are positioned to the right of their predecessor)
    attributes[:float]
  end
  
  def float_h( base ) # float self (position in x-direction) relative to 'base'

    if origin.null? then # first call, no recursion yet
      origin.y = base.origin.y
      origin.x = base.x
    end
    
    if base.x + attributes[:width] > parentpage.parent.defaults[:pagewidth] - parentpage.margin_right then # the panel dosn't fit on the page horizontally; it has to be moved to the next line.      
      origin.x = base.origin.x
      origin.y = base.y
      self.float_v( base )  
    end
    
    if !base.previous.nil? && base.previous.x <= self.origin.x && origin.y != parentpage.margin_top then # slide this panel up by one (recursively)
      origin.y = base.previous.origin.y
      self.float_h( base.previous )
    end
    
    # if self.intersectsWith?( base ) then self.float_h( base.previous ) end
  end
  
  def float_v( base ) # float self (position in y-direction) relative to 'base'

    if origin.null? then
      origin.x = base.origin.x
      origin.y = base.y
    end

    if !base.previous.nil? && base.previous.y <= self.origin.y && origin.x != parentpage.margin_left then # we can slide this panel to the left by one (recursive case):
      origin.x = base.previous.origin.x
      self.float_v( base.previous )
    elsif base.y + attributes[:height] > parentpage.parent.defaults[:pageheight] - parentpage.margin_bottom then # the panel dosn't fit on the page anymore
      raise StandardError, "Panel #{attributes[:id]} doesn't fit on page #{parentpage.attributes[:id]}"
    end
     
  end
  
  def setSize!
    size.x = attributes[:width]
    size.y = attributes[:height]
    if size.x == 0 then size.x = parentpage.parent.defaults[:pagewidth] - parentpage.margin_right - origin.x end
    if size.y == 0 then size.y = parentpage.parent.defaults[:pageheight] - parentpage.margin_bottom - origin.y end
  end
  
  def previous
    i = parentpage.panels.index(self) - 1
    if i < 0 then
      nil
    else
      parentpage.panels[ i ]
    end
  end
  
  def intersectsWith?( frame )
    x > frame.origin.x && y > frame.origin.y
  end
  
  def x # Max extension of this panel in x-direction
    origin.x + size.x
  end
  
  def y # Max extension of this panel in y-direction
    origin.y + size.y
  end
  
end  

# Points are used to store the coordinates and width and height of a panel
class Point
  
  attr_accessor :x, :y
  
  def initialize(*args)  
    unless args.size == 2  || args.size == 0  
      raise StandardError, "the Point-initializer takes either two arguments or none." 
    else  
      if args.size == 2  
        @x = args[0]
        @y = args[1] 
      else  
        @x = 0
        @y = 0 
      end  
    end  
  end
  
  def +(point)
    Point.new( x + point.x, y + point.y )
  end
  
  def -(point)
    Point.new( x - point.x, y - point.y )
  end
  
  def ==(point)
    if x == point.x && y == point.y then true else false end
  end
  
  def null?
    x == 0 && y == 0
  end
  
end


# ----------------------------------------------------
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

# instantiate a new comic with a comic file from the commandline options
comic = Comic.new( options[:file] )

# generate some output - like an indesign-file or a pdf
comic.generate( options[:target] )

