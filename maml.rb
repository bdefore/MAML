#!/usr/bin/env ruby
#
# Author:   Buck DeFore
# Version:  ASYMPTOTIC TO ZERO
#
# See README for more info: https://github.com/bdefore/MAML
#
# MIT License
# 
# Copyright (c) 2011 Buck DeFore
# 
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require 'optparse'
require 'ostruct'
require 'fileutils.rb'
require 'rstakeout.rb'

$options = OpenStruct.new(:verbose => false, :output_path => "maml_generated", :watch_mode => false, :sleep_time => 1, :synchronous => false, :indent_size => 2, :dry_run => false)

OptionParser.new do |opts|
  opts.banner = "Usage: maml.rb [options] <command> <filespec>+"
  opts.on("-v", "--verbose") do |v|
    $options.verbose = v
  end
  opts.on("-o", "--output-path PATH", String) do |o|
    $options.output_path = o
  end
  opts.on("-w", "--watch-mode") do |w|
    $options.watch_mode = w
  end
  opts.on("-d", "--dry-run") do |d|
    $options.dry_run = d
  end
  opts.on("-t", "--sleep-time T", Integer, "time to sleep after each loop iteration") do |t|
    $options.sleep_time = t
  end
  opts.on("--indent-size T", Integer, "How many spaces to indent per nested level") do |t|
    $options.sleep_time = t
  end
  if($options.verbose)
    puts $options
  end
end.parse!

def to_maml(input_path, output_path)

  result = ""
  File.readlines( input_path, 'r' ).each do |line|
    result += line
  end

  # Strip <fx:Script> node off, put at end later. For now only fx namespace allowed for Script
  # scriptMatch = /(<fx:Script>)([\s\S]+)^(<\/fx:Script>)/
  script_indicator = "<☠:☠>"
  metadata_indicator = "<☠☠:☠☠>"

  # TO FIX: 'fx' namespace is currently required for Script tag. This is because the search/replace
  # uses slice! and start/stop indexes, and needs a string to add the additional string length to the
  # amount being sliced. Probably a better way to do this that would give us namespace agnosticism
  # using the line underneath instead
  # 
  # NOTE: Start index is missing closing bracket to account for Flash Builder skinning 
  # declaration i.e. <fx:Script fb:purpose="styling">
  #
  # scriptNodes = slice_all_nodes(result, /<([A-Za-z0-9:]+)?Script/, /<\/([A-Za-z0-9:]+)Script>/, cdata_indicator)
  scriptNodes = slice_all_nodes(result, /<fx:Script/, "</fx:Script>", script_indicator)
  scriptNodes += slice_all_nodes(result, /<mx:Script/, "</mx:Script>", script_indicator)
  metadataNodes = slice_all_nodes(result, /<fx:Metadata>/, "</fx:Metadata>", metadata_indicator)
  metadataNodes += slice_all_nodes(result, /<mx:Metadata>/, "</mx:Metadata>", metadata_indicator)
  
  # Strip off <?xml version="1.0" encoding="utf-8"?>
  declarations = slice_node(result, "<?", "?>")
  # Strip comments
  comments = slice_all_nodes(result, "<!--", "-->")
  if(comments.length > 0)
    puts "WARNING: Stripped " + String(comments.length) + " comment(s) when converting from " + input_path
  end

  # MXML metadata interferes with node split of "><"
  # An unideal solution - tuck metadata into the role of attribute before MAML parsing begins
  #      ' MXML_METADATA="[\\1(\'\\2\')]" >'
  # mxmlMetadata = />[\s]+\[([A-Za-z ]+)\([''"]([\s\S]+)[''"]\)\]/
  # match_index = result.index(mxmlMetadata)
  # begin
  #   if match_index
  #     match = result.match(mxmlMetadata)
  #     match[0].gsub!(/^>[\s]+/, "")
  #     metadata_pieces = match[0].split("[")[1].split("]");
  #     metadata_pieces.each do |metadata|
  #     end
  #     while metadata_pieces.length > 0
  #       metadata_piece = metadata_pieces.shift
  #       metadata_piece_formatted = "[" + metadata_piece + "]"
  #       metadata_piece_formatted.gsub!('"', "'")
  #       result = result.gsub("[" + metadata_piece + "]", '<fx:MAML metadata="' + metadata_piece_formatted + '" />');
  #     end
  #   end
  #   match_index = result.index(mxmlMetadata)
  # end while match_index
  
  # Remove all whitespace outside of tags and between attributes, outside of CDATA

  result = result.gsub(/\>[\s]+\</, "><")
  result = result.gsub(/[\n\t]/, " ")
  result = result.gsub(/[\s]+/, " ")
  result = result.gsub(/^[\s]+/, "") # leading whitespace before content breaks things

  # Convert self closing tags to open and closed tags

  result = result.gsub(/[^>]<([A-Za-z0-9]+):([A-Za-z0-9]+) ([^>]+) \/>/, "\\1:\\2 \\3>\n</\\1:\\2>");
  
  # Persist an indentation value, ++ every time a closing tag is found, -- when the tag that initiated the increment is closed.
  indents = 0
  nestedResult = ""
  result = result[1..result.length]
  result = result.split(/\>\</)

  begin
    nestedLevel = result.shift
    
    # For those MXML nodes that have legitmate values rather than attributes, assign them to the value
    # property.
    #
    # i.e. <mx:String>Helvetica</mx:String>
    if nestedLevel.split(/</).length > 1
      kibblesAndBits = nestedLevel.split(/</).join("☠").split(/>/).join("☠").split("☠")
      nestedLevel = kibblesAndBits[0] + ' mxml_node_value="' + kibblesAndBits[1] + '" /'
    end
    
    # put the split target back on
    nestedLevel = "<" + nestedLevel + ">\n"

    if nestedLevel.index(script_indicator)

      script = scriptNodes.shift
      tag = ""
      lines = script.split("\n")
      indent_in_spaces = "".rjust($options.indent_size)
      begin
        line = lines.shift
        line = line.rjust(line.length + indents * $options.indent_size)
        line = line.gsub(/\t/, indent_in_spaces)
        line += "\n"
        tag += line
      end while lines.length > 0
      tag += "\n"
      nestedResult += tag

    elsif nestedLevel.index(metadata_indicator)
      
      metadata = metadataNodes.shift
      tag = ""
      lines = metadata.split("\n")
      indent_in_spaces = "".rjust($options.indent_size)
      begin
        line = lines.shift
        line = line.rjust(line.length + indents * $options.indent_size)
        line = line.gsub(/\t/, indent_in_spaces)
        line += "\n"
        tag += line
      end while lines.length > 0
      tag += "\n"
      nestedResult += tag

    else
      # determine kind of node
      selfClosingNode = nestedLevel.index(/\/>/)
      closingNode = nestedLevel.index(/<\//)
      openingNode = !closingNode

      # revert earlier increment if this is closing node of an earlier open one
      if closingNode
        indents -= 1
      end
      
      # now that we've got a read on how far to indent, remove brackets
      nestedLevel = nestedLevel.gsub(/<\//, "");
      nestedLevel = nestedLevel.gsub(/\/>/, "");
      nestedLevel = nestedLevel.gsub(/[\s]+>/, ">"); # whitespace before closing tag breaks the attribute split
      nestedLevel = nestedLevel.gsub(/[<>]/, "");

      # ensure one space between any = operator 
      nestedLevel = nestedLevel.gsub(/([\S])\=([\S])/, "\\1 = \\2")

      # split between class name and attributes
      twoHalves = nestedLevel.split(" ", 2)
      klass = twoHalves[0]
      attrNameValuePairs = twoHalves[1].split("\"");

      # pad with indentation at this level
      klass = klass.rjust(klass.length + (indents*$options.indent_size))
    
      nestedLevelWithAttrs = klass;

      # find largest attribute name in order to pad correctly
      largestAttrNameLength = 0;

      attrs = []
      while attrNameValuePairs.length > 0
        name = attrNameValuePairs.shift()
        value = attrNameValuePairs.shift()
        if(name && value)
          name = name.lstrip
          largestAttrNameLength = [ name.index(/\=/), largestAttrNameLength ].max;
          attrs.push(name + value)
        end
      end

      attrs.each do |attr|
        # - Outdent attribute values to the position just right of the longest named attribute
        attrHalves = attr.split(" = ");
        attrName = attrHalves[0]
        attrValue = attrHalves[1] || ""
        toPad = largestAttrNameLength - attrName.length - 1
        paddedAttr = attrName.ljust(attrName.length + toPad) + " = " + attrValue;
        indentedAttr = paddedAttr.rjust(paddedAttr.length + (indents*$options.indent_size))
        nestedLevelWithAttrs += "\n" + indentedAttr
      end
  
      nestedLevelWithAttrs += "\n\n"

      # append to accumulating string, ixnay the closing nodes for this formatting style
      if openingNode

        nestedResult += nestedLevelWithAttrs
      end

      # increment indentation for next node if this one never closed
      if openingNode
        indents += 1
      end

      # self-closers
      if selfClosingNode
        indents -= 1
      end
    end
  end while result.length > 0
  
  output = nestedResult 

  write output, output_path

end

def to_mxml(input_path, output_path)

  # TO FIX: When two empty lines are in order, parsing breaks

  mxmlNode = MxmlNode.new
  mxmlNode.attributes = []
  mxmlNode.cdata = ""
  mxmlNodes = []
  isObjectDeclarationLine = true # first object must always be first line

  result = ""
  File.readlines( input_path, 'r' ).each do |line|
    result += line
  end

  lines = result.split("\n")
  
  while lines.length > 0
    line = lines.shift
    whitespace = line.match(/^[ ]+/);
    
    if(whitespace)
      # MatchData object contains full match in 0 index
      mxmlNode.indent = whitespace[0].length
    else
      mxmlNode.indent = 0
    end

    # TO FIX: Shouldn't need three variations on the FB tools hack. Find a better way to survive
    # additional spaces within this tag
    cdata_classes = [ "Script>", 'Script fb:purpose="styling">', 'Script fb:purpose="styling" >', 'Script  fb:purpose="styling" >', "Metadata>"]

    # if it's an empty line, signifies end of mxml node
    if line.length == 0
      if mxmlNode.klass
        mxmlNodes.push(mxmlNode)
        mxmlNode = MxmlNode.new
        mxmlNode.attributes = []
        mxmlNode.cdata = ""
      end
      
      isObjectDeclarationLine = true
    else
      if isObjectDeclarationLine
        strippedLine = line.lstrip.rstrip
        if strippedLine.index(/\:/)
          tempArr = strippedLine.split(/\:/, 2)
          mxmlNode.namespace = tempArr[0]
          mxmlNode.klass = tempArr[1]
          # Inelegant. Fix?
          # CDATA nodes must maintain bracket structure because a whitespace parser knows not when 
          # they terminate otherwise. As such, this workaround prevents duplicate brackets being
          # thrown on them
          cdata_classes.each do |cdata_class|
            if mxmlNode.klass == cdata_class
              mxmlNode.namespace.slice!(0) # leading <
              mxmlNode.klass.slice!(mxmlNode.klass.length - 1) # trailing >

              # Sad sad little hack around an Adobe hack
              since_fb_styling_closes_without_attribute = cdata_class.split(" ")[0]

              line = lines.shift
              while !line.index since_fb_styling_closes_without_attribute
                mxmlNode.cdata += line
                line = lines.shift + "\n"
              end
            end
          end
        else
          puts "WARNING: Found MXML node without namespace declaration. This is currently experimental support!"
          puts "Affected line: " + strippedLine
          mxmlNode.namespace = ""
          mxmlNode.klass = strippedLine
        end
        # further lines before empty line are attributes
        # indicate that to the logic here
        isObjectDeclarationLine = false
      else
        # is attribute line

        line.strip!
        nameValuePair = line.split("=");
        name = nameValuePair[0]
        value = nameValuePair[1]
        # some mxml values are empty strings (i.e. text=""). these can be incorrectly assigned
        # to nil if we're not careful. worth a warning though that it could be due to a parse
        # problem
        if !value
          puts "WARNING: Property " + name.rstrip! + " evaluated to nil on file " + input_path + ". This may normal if you set to an empty string, which is what it will be assigned to."
          value = ""
        end
        name.rstrip!
        value.lstrip!

        attribute = MxmlNodeAttribute.new
        attribute.name = name
        attribute.value = value
        
        mxmlNode.attributes.push( attribute )
      end
    end
  end

  # if file does not end with a new line, the above loop does not
  # push the final node it's building. we check that here
  if(!isObjectDeclarationLine)
    mxmlNodes.push(mxmlNode)
  end

  # parse into mxml bracket notation
  fullOutput = ""
  nodesToCloseYet = []

  # we first pop off the mother node since she has no indentation
  # and no children that would trigger her to output her open node
  containerNode = mxmlNodes.shift()
  if(containerNode)
    containerNode.indent = 0
    fullOutput = open_mxml_node(containerNode)
    nodesToCloseYet.push(containerNode)
  end

  mxmlNodes.each do |mxmlNode|

    openingNode = open_mxml_node(mxmlNode)

    parentNodeFound = false
    while !parentNodeFound && nodesToCloseYet.length > 0
      
      nodeToClose = nodesToCloseYet.pop();
      
      if nodeToClose.indent >= mxmlNode.indent
        # nodeToClose is a child of previous node close it first then 
        # continue through set of nodesToClose seeking parent

        # puts "Found child of previous node that needs closing: " + nodeToClose.klass + " before " + mxmlNode.klass
        fullOutput += close_mxml_node(nodeToClose)

      elsif nodeToClose.indent == mxmlNode.indent
        # nodeToClose is a sibling. close it first then 
        # continue through set of nodesToClose seeking parent

        # puts "Found sibling: " + nodeToClose.klass + " of " + mxmlNode.klass
        fullOutput += close_mxml_node(nodeToClose)

      else
        # the nodeToClose is the parent of the current node. not ready to close yet
        # we may now write out the opening node which we are currently iterating through
        
        fullOutput += openingNode
        nodesToCloseYet.push(nodeToClose)
        parentNodeFound = true;
      end
    end

    # store closing tag, will wait to output until next object has less indentation
    nodesToCloseYet.push(mxmlNode);

  end

  # whatever parent node(s) did not have children were not found in the loop above
  # they need to be closed out now
  while nodesToCloseYet.length > 0
    fullOutput += close_mxml_node(nodesToCloseYet.pop())
  end

  write fullOutput, output_path

end

def slice_all_nodes(base_string, start_match, end_match, replace_with=nil)
  results = []
  while base_string.index(start_match)
    results.push(slice_node(base_string, start_match, end_match, replace_with));
  end
  return results
end

def slice_node(base_string, start_match, end_match, replace_with=nil)
  start_point = base_string.index(start_match)
  if(start_point)
    end_point = base_string.index(end_match, start_point)

    if(end_point)
      end_point += end_match.length

      if(base_string && start_point && end_point)
        result = base_string.slice!(start_point..end_point)
        if(replace_with)
          base_string.insert(start_point, replace_with)
        end
      end
    end
  end
  
  return result
end

def open_mxml_node(mxmlNode)
  metadata = ""
  attributeString = ""
  cdata = mxmlNode.cdata

  mxmlNode.attributes.each do |attribute|
    if attribute.name == "MXML_METADATA"
      metadata = attribute.value;
      metadata = metadata.rjust(metadata.length + mxmlNode.indent + $options.indent_size)
      metadata += "\n"
    else
      attributeString += " " + attribute.name + "=\"" + attribute.value + "\""
    end
  end

  opener = "<"
  closer = ">"
  openingNode = opener + mxmlNode.namespace + ":" + mxmlNode.klass
  openingNode = openingNode.rjust(openingNode.length + mxmlNode.indent);

  total = openingNode + attributeString
  total += closer + "\n" + metadata + cdata
  
  return total
end

def close_mxml_node(mxmlNode)
  opener = "</"
  closer = ">"

  closingOutput = opener + mxmlNode.namespace + ":" + mxmlNode.klass + closer
  closingOutput = closingOutput.rjust(closingOutput.length + mxmlNode.indent) + "\n"
  return closingOutput
end

def write(output, output_path)

  if !output || output == ""
    puts "=========================================================="
    puts "== Nothing to output!"
    puts "=========================================================="
  elsif !output_path || $options.dry_run
    puts "=========================================================="
    puts "== Dry run begins for target destination: " + output_path
    puts "=========================================================="
    puts output
    puts "=========================================================="
    puts "== Dry run complete for target destination: " + output_path
    puts "=========================================================="
  else
    dirname = File.dirname(output_path)
    if !File.exist?(dirname)
      if $options.verbose
        puts "Creating directory: " + dirname
      end
      FileUtils.mkpath dirname
    end

    if !File.directory?(output_path)
      f = File.new(output_path, "w")
      f.puts output
      f.close
      if $options.verbose
        puts "Written successfully to " + output_path
      end
    end
  end
end

class MxmlNode
  def initialize()
  end
  attr_reader :lindent, :indent
  attr_writer :lindent, :indent
  attr_reader :lnamespace, :namespace
  attr_writer :lnamespace, :namespace
  attr_reader :lklass, :klass
  attr_writer :lklass, :klass
  attr_reader :lattributes, :attributes
  attr_writer :lattributes, :attributes
  attr_reader :lvalue, :value
  attr_writer :lvalue, :value
  attr_reader :lcdata, :cdata
  attr_writer :lcdata, :cdata
end

class MxmlNodeAttribute
  def initialize()
  end
  attr_reader :lname, :name
  attr_writer :lname, :name
  attr_reader :lvalue, :value
  attr_writer :lvalue, :value
end

def convert(input_path)
  puts "Opening file at " + input_path
  if input_path.upcase.index(/MXML/)
    to_maml input_path, $options.output_path + "/maml/" + input_path.gsub(".mxml", ".maml")
  elsif input_path.upcase.index(/MAML/)
    to_mxml input_path, $options.output_path + "/mxml/" + input_path.gsub(".maml", ".mxml")
  end
end

def convert_files(files)
  if files
    if $options.verbose 
      puts "Building #{files.keys.join(', ')}\n\nTOTAL FILES: #{files.keys.length}\n\n"
    end
    fileArgString = ""
    files.each do |file|
      # only pass in file names to convert, not dirs
      if !File.directory?(file[0])
        convert(file[0])
        fileArgString += file[0] + " "
      end
    end
    if $options.watch_mode
      stakeout_command = "ruby maml.rb " + fileArgString
      watch(stakeout_command, files, $options)
    end
  else
    puts "================================================="
    puts "== maml.rb version ASYMPTOTIC TO ZERO"
    puts "================================================="
    puts "== Expecting a mxml or maml file"
    puts "================================================="
  end  
end

def build_mtimes_hash(file_paths)
  files = {}
  file_paths.each { |file_path|
    Dir[file_path].each { |file| files[file] = File.mtime(file) }
  }
  files
end

input_path = ARGV.pop;
if !input_path
  puts "================================================="
  puts "== maml.rb version ASYMPTOTIC TO ZERO"
  puts "================================================="
  puts "== Please specify a path to an MXML or MAML file,"
  puts "== and optionally a path to output to."
  puts "================================================="
elsif(File.directory?(input_path))
  file_paths = Dir[input_path + "/**/*.mxml"]
  file_paths += Dir[input_path + "/**/*.maml"]
else
  file_paths = [ input_path ]
end

files = build_mtimes_hash(file_paths)

beginning_time = Time.now
convert_files(files)
end_time = Time.now
puts "Completed in #{(end_time - beginning_time)*1000} milliseconds"