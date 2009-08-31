#!/usr/bin/ruby

require 'rubygems'
require 'hpricot'
require 'appscript'
include Appscript

file = "./starman_jones"

# define comic structure

class Comic
  
  attr_accessor :defaults, :pages
  
  def initialize
    @defaults = Hash.new
    @pages = Array.new
  end
end

class Page

  attr_accessor :id, :description, :panels

  def initialize
    @id = 0
    @description = ""
    @panels = Array.new
  end
end  

class Panel
  
  attr_accessor :id, :description, :text
  
  def initialize
    @id = 0
    @description = ""
    @text = Array.new
  end
end  


# load comic file
result = Hpricot(open(file))

resultHash = {}

# Liste der Motorräder in einem Hash Speichern
result.search("div .col-content > table > tbody > tr").each do |col|
 
  entry = {}
  
  link = col.search('.infoLink').first
  link.to_s =~ /<a\shref=\"(.*?)\"/
  entry[:link] = $1  
  entry[:description] = col.search('.description > div h5').inner_html.to_s.strip
  entry[:first_reg] = col.search('.first-registration').inner_html.to_s.delete("EZ ").chomp
  entry[:mileage] = col.search('.mileage').inner_html.to_s.delete("&nbsp;km").strip
  entry[:price] = col.search('.priceBlack').inner_html.to_s.delete("EUR ").chomp


  id = entry[:first_reg] + "|" + entry[:mileage] + "|" + entry[:price]
  
  unless id.length <= 2 || entry[:description] =~ /RS|RT|GS/ then 
    resultHash[id.to_sym] = entry 
  end
  
end

# in Datei gespeicherte Motorräder laden
kradFile = YAML.load_file path + "krad.yml"

# Vergleich der Motorräder auf der Website mit denen aus der Datei.
# Sind neue Motorräder dazu gekommen?
newKrad = {}
resultHash.each_pair do |id, krad|
  unless kradFile.has_key?(id) then # Motorrad noch unbekannt?
    newKrad[id] = krad
    app('Safari').open_location( krad[:link] ) # Link zum neuen Motorrad in Safari öffnen
  end
end

# Wenn neue Motorräder da sind: Datei neu speichern!
if newKrad.length > 0 then
  File.open( path + "newkrad.yml", 'w') { |f| YAML.dump(newKrad, f) } 
  File.open( path + "krad.yml", 'w') { |f| YAML.dump(resultHash.merge(kradFile), f) } 
else
  # puts "nix neues bei mobile.de\n"
end
