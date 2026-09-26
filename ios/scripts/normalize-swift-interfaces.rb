# Work around Swift's module/type name collision without renaming the public API.
# Only self-module qualification of declared top-level types is removed. Keep
# strings/comments and genuine THKMDView static member references untouched.
module THKSwiftInterfaces
  def self.normalize(source)
    names = source.lines.reject { |line| line.start_with?(' ', "\t") }
      .map { |line| line[/\bpublic\s+(?:(?:final|indirect)\s+)?(?:class|struct|enum|protocol|typealias)\s+([A-Za-z_][A-Za-z_0-9]*)/, 1] }.compact
    raise 'Missing public THKMDView declaration' unless names.include?('THKMDView')
    qualified_type = /\bTHKMDView\.(?:#{names.map { |name| Regexp.escape(name) }.join('|')})\b/
    tokens = %r{//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|#{qualified_type}}m
    source.gsub(tokens) { |token| token.start_with?('THKMDView.') ? token.delete_prefix('THKMDView.') : token }
  end
end

if $PROGRAM_NAME == __FILE__
  directory = ARGV.fetch(0)
  files = Dir.glob(File.join(directory, '*.swiftinterface'))
  abort "No Swift interfaces in #{directory}" if files.empty?
  files.each { |path| File.write(path, THKSwiftInterfaces.normalize(File.read(path))) }
end
