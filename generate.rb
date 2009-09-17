#!/usr/bin/ruby

require 'rubygems'
require 'yaml'
require 'optparse'
require 'hpricot'
require 'appscript'
require 'RMagick'
include Appscript
include Magick


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
        if key == "id" then
          @defaults[key.to_sym] = value.to_s
        else
          @defaults[key.to_sym] = value.to_f
        end
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
      
      puts "generating indesign document..."
      
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
      layer = Hash.new
      [ "background", "panels", "text boxes", "speech bubbles"].each do |layername|
        layer[layername.gsub(/\s/, "_").to_sym] = doc.make( :new => :layer, :with_properties => { :name => layername } )
      end
      
      div2 = @defaults[:dividerwidth] / 2
      dpmm = @defaults[:resolution] / 25.4
      
      pages.each do |p|
        p.panels.each do |panel|
          frame = doc.pages[p.attributes[:id]].make( :new => :rectangle, :with_properties => {   
            :item_layer => layer[:panels],            
            :geometric_bounds => [
              panel.origin.y + div2, 
              panel.origin.x + div2, 
              panel.origin.y + panel.size.y - div2, 
              panel.origin.x + panel.size.x - div2  ], 
            :stroke_color => "Black",
            :stroke_weight => 2
          })
          
          imgFolder = "images#{@defaults[:id]}"
          pageFolder = "#{imgFolder}/page#{p.attributes[:id]}"
          filename = "#{pageFolder}/panel#{p.attributes[:id]}_#{panel.attributes[:id]}.png"
          
          if File::exists?( filename ) then
            frame.place( 
              MacTypes::Alias.path( filename ),
              :destination_layer => layer[:panels],
              :with_properties => { 
                :geometric_bounds => [
                  panel.origin.y + div2 - defaults[:imageborder]/dpmm, 
                  panel.origin.x + div2 - defaults[:imageborder]/dpmm, 
                  panel.origin.y + panel.size.y - div2 + defaults[:imageborder]/dpmm, 
                  panel.origin.x + panel.size.x - div2 + defaults[:imageborder]/dpmm  ],
              }
            )
          end
          
          panel.text.each do |text|
            textframe = doc.pages[p.attributes[:id]].make( :new => :text_frame, :with_properties => { 
              :inset_spacing => [5,5,5,5],  
              :item_layer => layer[:text_boxes],    
              :contents => text[:content],
              :geometric_bounds => [
                panel.origin.y + @defaults[:dividerwidth], 
                panel.origin.x + @defaults[:dividerwidth], 
                panel.origin.y + panel.size.y - div2, 
                panel.origin.x + panel.size.x - div2  ],                      
              :stroke_color => "Black",
              :stroke_weight => 2
            })
            textframe.text_frame_preferences.inset_spacing.set [div2,div2,div2,div2]
            textframe.fit :given => :frame_to_content
          end
          
        end
      end
      
    elsif target == :images then
      puts "generating images..."
      
      
      dpmm = defaults[:resolution] / 25.4 # "Dots per mm" – 300dpi / 25.4 (mm per inch)
      imgFolder = "images#{@defaults[:id]}"
      
      unless File::directory?( imgFolder ) then
        Dir.mkdir( imgFolder )
      end
      
      pages.each do |page|
        pageFolder = "#{imgFolder}/page#{page.attributes[:id]}"
        unless File::directory?( pageFolder ) then
          Dir.mkdir( pageFolder )
        end
               
        page.panels.each do |panel|
          filename = "#{pageFolder}/panel#{page.attributes[:id]}_#{panel.attributes[:id]}.png"
          unless File::exists?( filename )
            
            border = defaults[:imageborder]
            px = panel.size.x * dpmm
            py = panel.size.y * dpmm
            
            img = Image.new( px + border*2, py + border*2 ) {
              self.background_color = 'white'
            }
          
            d = Draw.new
          
            d.fill("#888888")
            d.line(border, border*2, border, border)
            d.line(border, border, border*2, border)
            d.line(px, py+border, px+border, py+border)
            d.line(px+border, py+border, px+border, py)
            
            d.font_family('Georgia')
            d.font_weight(Magick::NormalWeight)
            d.pointsize(9)
            d.font_style(Magick::NormalStyle)
            d.gravity(Magick::SouthWestGravity)
          
            if panel.attributes[:description] then
              d.text( border, border-10, "#{panel.attributes[:description]}")
            end
            
            d.draw( img )

            img.write( filename )
          end
        end
      end 
      
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
    panels.each do |panel| 
      panel.arrange! 
    end
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
      self.setSize!
    elsif self.float? then
      self.float_h( self.previous ) # position a panel on the right side of it's predecessor
    else # panel not floating
      self.float_v( self.previous ) # position a panel below its predecessor
    end 
    parentpage.panels.each do |p|
      if p != self && self.intersectsWith?( p ) then # does it intersect with anything?
        self.origin.y = p.y # in this case move it down below the "offending" panel
        begin    
          slideup   = self.slide_up!       
          slideleft = self.slide_left! 
        end while slideup || slideleft
      end
    end  
  end
  
  def float? # by default, panels float (are positioned to the right of their predecessor)
    attributes[:float]
  end

# ----------------------------------------------
  
  def float_h( base ) # float self (position in x-direction) relative to 'base'  
    origin.y = base.origin.y
    origin.x = base.x
    if base.x + attributes[:width] > parentpage.parent.defaults[:pagewidth] - parentpage.margin_right then # the panel dosn't fit on the page horizontally; it has to be moved to the next line.      
      self.float_v( base )  
    end
    self.setSize!
    begin    
      slideup   = self.slide_up!       
      slideleft = self.slide_left! 
    end while slideup || slideleft
  end
  
  def float_v( base ) # float self (position in y-direction) relative to 'base'
    origin.x = base.origin.x
    origin.y = base.y
    self.setSize!
    begin     
      slideleft = self.slide_left!      
      slideup   = self.slide_up!        
    end while slideup || slideleft
  end

# ----------------------------------------------
  
  def slide_up!
    # get the panel with the next smaller y-coordinate
    list = parentpage.panels.reject{ |panel| panel.origin.y >= self.origin.y || panel.origin.y == 0 }
    
    if list.size > 0 then
      newbase = list.sort!{ |p1,p2|  
        if p1.y >= self.origin.y then
          a = p1.origin.y
        else 
          a = p1.y
        end
        if p2.y >= self.origin.y then
          b = p2.origin.y
        else 
          b = p2.y
        end
        a <=> b 
      }.last
      
      # position a copy of self relative to it
      c = self.clone
      
      if self.origin.y <= newbase.y then
        c.origin.y = newbase.origin.y
      else
        c.origin.y = newbase.y
      end
      
      # does it intersect with anything?
      parentpage.panels.each do |p|
        if p != self && c.intersectsWith?( p ) then # yes, it does: no sliding to be done. return false.
          return false
        end
      end
      
      # no, it doesn't: adopt the new coordinates
      self.origin.y = c.origin.y
      return true
      
    else
      return false
    end
  end
  
  def slide_left!
    # get the panel with the next smaller y-coordinate
    list = parentpage.panels.reject{ |panel| panel.origin.x >= self.origin.x || panel.origin.x == 0 }

    if list.size > 0 then
      newbase = list.sort!{ |p1,p2|  
        if p1.x >= self.origin.x then
          a = p1.origin.x
        else 
          a = p1.x
        end
        if p2.x >= self.origin.x then
          b = p2.origin.x
        else 
          b = p2.x
        end
        a <=> b 
      }.last
      
      # position a copy of self relative to it
      c = self.clone
      
      if self.origin.x <= newbase.x then
        c.origin.x = newbase.origin.x
      else
        c.origin.x = newbase.x
      end

      # does it intersect with anything?
      parentpage.panels.each do |p|
        if p != self && c.intersectsWith?( p ) then # yes, it does: no sliding up. return false.
          return false
        end
      end
      
      # no, it doesn't: adopt the new coordinates
      self.origin.x = c.origin.x
      return true

    else
      return false
    end
  end
  
  # when a panel is "trapped" on three sides, it may be necessary to slide it down until there is enough space for it.
  # the neccessity to slide right may in fact occur, but it shouldn't for the purposes of common comic reading order.
  def slide_down( base ) 
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
  
  def intersectsWith?( panel )
    [x, panel.x].min > [origin.x, panel.origin.x].max && [y, panel.y].min > [origin.y, panel.origin.y].max
  end
  
  def x # Max extension of this panel in x-direction
    origin.x + size.x
  end
  
  def y # Max extension of this panel in y-direction
    origin.y + size.y
  end
  
  def clone
    cl = Panel.new( self.parentpage )
    cl.attributes = self.attributes.clone
    cl.text = self.text
    cl.size = self.size.clone
    cl.origin = self.origin.clone
    return cl
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
  
  #redundant?
  def clone
    Point.new( x, y )
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

