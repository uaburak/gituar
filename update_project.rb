require 'xcodeproj'

project_path = 'Gituar.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the main app target
target = project.targets.find { |t| t.name == 'Gituar' } || project.targets.first

# Find the Views group
gituar_group = project.main_group.children.find { |c| c.display_name == 'Gituar' || c.path == 'Gituar' }
views_group = gituar_group.children.find { |c| c.display_name == 'Views' || c.path == 'Views' }

files_to_add = [
  'HomeComponents.swift',
  'GenericSongListView.swift',
  'GenericRepertoireListView.swift',
  'AllArtistsView.swift',
  'PopularChordsView.swift',
  'ArtistDetailView.swift'
]

files_to_add.each do |file_name|
  file_ref = views_group.files.find { |f| f.path == file_name }
  if file_ref.nil?
    file_ref = views_group.new_file(file_name)
    target.source_build_phase.add_file_reference(file_ref, true)
  end
end

# Remove NativeAdView.swift
native_ad_ref = views_group.files.find { |f| f.path == 'NativeAdView.swift' }
if native_ad_ref
  target.source_build_phase.remove_file_reference(native_ad_ref)
  native_ad_ref.remove_from_project
end

project.save
puts 'Project updated successfully.'
