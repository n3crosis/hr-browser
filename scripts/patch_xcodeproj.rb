#!/usr/bin/env ruby

require 'fileutils'
begin
  require 'xcodeproj'
rescue LoadError
  abort("ERROR: 'xcodeproj' gem is missing. Please run 'gem install xcodeproj' or install via Bundler.")
end

if ARGV.length != 1
  abort("Usage: ruby patch_xcodeproj.rb <path/to/focus-ios/>")
end

focus_dir = ARGV[0]
project_path = File.join(focus_dir, "Blockzilla.xcodeproj")
widget_dir = File.join(focus_dir, "Blockzilla", "FloatingWidget")

team_id = ENV['TEAM_ID']
if team_id.nil? || team_id.empty?
  abort("ERROR: TEAM_ID environment variable is not set or empty.\n" +
        "       Run via apply-focus-enterprise.sh or set: export TEAM_ID=<your-10-char-id>")
end

app_name = ENV['APP_NAME']
if app_name.nil? || app_name.empty?
  abort("ERROR: APP_NAME environment variable is not set or empty.\n" +
        "       Run via apply-focus-enterprise.sh or set: export APP_NAME=<your-app-name>")
end

unless File.exist?(project_path)
  abort("ERROR: Could not find #{project_path}")
end

project = Xcodeproj::Project.open(project_path)

# MARK: - Remove non-English localizations
if project.root_object
  project.root_object.known_regions = ["en", "Base"]
end

project.objects.select { |obj| obj.is_a?(Xcodeproj::Project::Object::PBXVariantGroup) }.each do |variant_group|
  children_to_remove = variant_group.children.select do |file_ref|
    name = file_ref.name || file_ref.path
    name && name != "en" && name != "Base"
  end
  
  children_to_remove.each do |child|
    child.remove_from_project
  end
end

# MARK: - Build settings patch
firefox_names = ["Firefox Focus", "Firefox Klar"]

exact_keys_to_remove = [
  "DEVELOPMENT_TEAM[sdk=iphoneos*]",
  "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]",
  "CODE_SIGN_IDENTITY[sdk=iphoneos*]",
  "PROVISIONING_PROFILE"
]

prefix_keys_to_remove = ["PROVISIONING_PROFILE_SPECIFIER"]

project.build_configurations.each do |config|
  s = config.build_settings
  
  s["DEVELOPMENT_TEAM"] = team_id
  s["CODE_SIGN_STYLE"] = "Automatic"
  
  exact_keys_to_remove.each { |k| s.delete(k) }
  s.delete_if { |k, _| prefix_keys_to_remove.any? { |prefix| k.start_with?(prefix) } }
  
  if firefox_names.include?(s["DISPLAY_NAME"])
    s["DISPLAY_NAME"] = app_name
  end
  if firefox_names.include?(s["PRODUCT_NAME"])
    s["PRODUCT_NAME"] = app_name
  end
  
  config.build_settings = s
end

# MARK: - FloatingWidget group + file registration
main_group = project.main_group
unless main_group
  abort("ERROR: No main group in project")
end

blockzilla_group = main_group.children.find { |g| g.is_a?(Xcodeproj::Project::Object::PBXGroup) && (g.name == "Blockzilla" || g.path == "Blockzilla") }
unless blockzilla_group
  abort("ERROR: 'Blockzilla' group not found in project navigator")
end

target = project.native_targets.find { |t| t.name == "Blockzilla" }
unless target
  abort("ERROR: 'Blockzilla' target not found")
end

target.build_configurations.each do |config|
  config.build_settings["CODE_SIGN_ENTITLEMENTS"] = "Blockzilla/Focus.entitlements"
end

if blockzilla_group.children.any? { |g| g.is_a?(Xcodeproj::Project::Object::PBXGroup) && (g.name == "FloatingWidget" || g.path == "FloatingWidget") }
  puts "FloatingWidget group already present — skipping file registration."
else
  sources_build_phase = target.source_build_phase
  unless sources_build_phase
    abort("ERROR: No Sources build phase on 'Blockzilla' target")
  end

  widget_group = project.new(Xcodeproj::Project::Object::PBXGroup)
  widget_group.name = "FloatingWidget"
  widget_group.path = "FloatingWidget"
  widget_group.source_tree = "<group>"
  blockzilla_group.children << widget_group

  source_files = []
  if File.directory?(widget_dir)
    Dir.glob(File.join(widget_dir, "*.{swift,m}")).each do |file|
      source_files << file
    end
  end

  source_files.each do |file_path|
    file_name = File.basename(file_path)
    
    file_ref = project.new(Xcodeproj::Project::Object::PBXFileReference)
    file_ref.name = file_name
    file_ref.path = file_name
    file_ref.source_tree = "<group>"
    
    if file_name.end_with?(".swift")
      file_ref.last_known_file_type = "sourcecode.swift"
    else
      file_ref.last_known_file_type = "sourcecode.c.objc"
    end
    
    widget_group.children << file_ref
    
    build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
    build_file.file_ref = file_ref
    sources_build_phase.files << build_file
  end
end

project.save
puts "OK: project.pbxproj updated (build settings + FloatingWidget files)."
