#!/usr/bin/env ruby
require 'fileutils'
require 'digest'
require 'time'

staging, destination, version = ARGV
abort 'Expected staging directory, destination directory and x.y.z version' unless
  staging && destination && version&.match?(/\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/)
relative = 'com/thk/mdview/thkmdview'
source = File.join(staging, relative, version)
target = File.join(destination, relative, version)
required = %W[thkmdview-#{version}.aar thkmdview-#{version}.pom thkmdview-#{version}.module thkmdview-#{version}-sources.jar]
required.each { |name| abort "Missing Maven artifact: #{name}" unless File.file?(File.join(source, name)) }
files = Dir.children(source).sort
abort 'Unexpected directory in Maven version' unless files.all? { |name| File.file?(File.join(source, name)) }
if File.exist?(target)
  identical = Dir.children(target).sort == files && files.all? do |name|
    FileUtils.compare_file(File.join(source, name), File.join(target, name))
  end
  abort "Refusing to overwrite published version #{version}" unless identical
  puts "Version #{version} already published with identical files"
  exit
end
FileUtils.mkdir_p(File.dirname(target))
FileUtils.cp_r(source, target)
root = File.dirname(target)
versions = Dir.children(root).select { |name| name.match?(/\A\d+\.\d+\.\d+\z/) && File.directory?(File.join(root, name)) }
versions.sort_by! { |name| name.split('.').map(&:to_i) }
metadata = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <metadata>
    <groupId>com.thk.mdview</groupId><artifactId>thkmdview</artifactId>
    <versioning>
      <latest>#{versions.last}</latest><release>#{versions.last}</release>
      <versions>#{versions.map { |name| "<version>#{name}</version>" }.join}</versions>
      <lastUpdated>#{Time.now.utc.strftime('%Y%m%d%H%M%S')}</lastUpdated>
    </versioning>
  </metadata>
XML
File.write(File.join(root, 'maven-metadata.xml'), metadata)
{ 'md5' => Digest::MD5, 'sha1' => Digest::SHA1, 'sha256' => Digest::SHA256, 'sha512' => Digest::SHA512 }.each do |suffix, digest|
  File.write(File.join(root, "maven-metadata.xml.#{suffix}"), digest.hexdigest(metadata))
end
puts "Added #{version}; preserved #{versions.length} version(s)"
