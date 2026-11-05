# Gituar.xcodeproj Xcode 16+ "synchronized folder" (PBXFileSystemSynchronizedRootGroup) kullanır:
# Gituar/ altındaki her dosya hedefe otomatik girer (Swift → Compile Sources, diğerleri → Copy Bundle Resources).
# Bu script yeni dosyaların o kök grubun kapsamında olduğunu doğrular; proje dosyasına yazmaz.
# Kullanım: ruby tools/add_files_to_xcode.rb Gituar/Utilities/PlusManager.swift Gituar/Resources/catalog.deflate
require 'xcodeproj'

project = Xcodeproj::Project.open('Gituar.xcodeproj')
target = project.targets.find { |t| t.name == 'Gituar' } || project.targets.first
synced = project.main_group.children.select { |c| c.isa == 'PBXFileSystemSynchronizedRootGroup' }
roots = synced.map { |g| g.path }
puts "Senkron kök gruplar: #{roots.inspect} (hedef: #{target.name})"

exceptions = synced.flat_map { |g| (g.respond_to?(:exceptions) ? g.exceptions : []) }
excluded = exceptions.flat_map { |e| e.respond_to?(:membership_exceptions) ? e.membership_exceptions : [] }
puts "Hedef dışı bırakılanlar: #{excluded.inspect}" unless excluded.empty?

status = 0
ARGV.each do |path|
  root = roots.find { |r| path.start_with?("#{r}/") }
  rel = root ? path.sub("#{root}/", '') : nil
  if root.nil?
    puts "✗ #{path}: senkron kök grup dışında — Xcode'da elle eklenmeli"
    status = 1
  elsif excluded.include?(rel)
    puts "✗ #{path}: membershipExceptions içinde, hedefe girmiyor"
    status = 1
  elsif !File.exist?(path)
    puts "✗ #{path}: dosya yok"
    status = 1
  else
    puts "✓ #{path}: '#{root}' senkron grubunda, hedefe otomatik dahil"
  end
end
exit status
