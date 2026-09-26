require 'tmpdir'
require 'fileutils'
require 'digest'
require 'rbconfig'

script = File.join(__dir__, 'merge-maven-repository.rb')
Dir.mktmpdir('thk-maven-test-') do |root|
  staging = File.join(root, 'staging')
  destination = File.join(root, 'repository')
  relative = 'com/thk/mdview/thkmdview'
  make_version = lambda do |version|
    path = File.join(staging, relative, version)
    FileUtils.mkdir_p(path)
    %w[aar pom module sources.jar].each do |extension|
      name = extension == 'sources.jar' ? "thkmdview-#{version}-sources.jar" : "thkmdview-#{version}.#{extension}"
      File.write(File.join(path, name), "fixture #{version} #{extension}")
    end
  end
  publish = ->(version) { system(RbConfig.ruby, script, staging, destination, version) }
  make_version.call('1.0.0')
  raise 'initial publish failed' unless publish.call('1.0.0')
  raise 'identical retry failed' unless publish.call('1.0.0')
  make_version.call('1.0.1')
  raise 'second publish failed' unless publish.call('1.0.1')
  metadata = File.read(File.join(destination, relative, 'maven-metadata.xml'))
  raise 'history lost' unless metadata.include?('<version>1.0.0</version>') && metadata.include?('<release>1.0.1</release>')
  checksum = File.read(File.join(destination, relative, 'maven-metadata.xml.sha256'))
  raise 'invalid checksum' unless checksum == Digest::SHA256.hexdigest(metadata)
  File.write(File.join(staging, relative, '1.0.0', 'thkmdview-1.0.0.aar'), 'changed')
  raise 'overwrite accepted' if publish.call('1.0.0')
  raise 'missing artifacts accepted' if publish.call('1.0.2')
end
puts 'Maven repository regression tests passed'
