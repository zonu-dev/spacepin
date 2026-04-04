#!/usr/bin/env ruby

require 'fileutils'
require 'pathname'
require 'xcodeproj'

ROOT = Pathname(__dir__).join('..').expand_path
PROJECT_PATH = ROOT.join('SpacePin.xcodeproj')
DEPLOYMENT_TARGET = '13.0'
APP_BUNDLE_ID = ENV.fetch('SPACEPIN_BUNDLE_ID', 'com.zoochigames.spacepin')
DEVELOPMENT_TEAM = ENV.fetch('SPACEPIN_TEAM_ID', 'TQW4K2Z6UW')
MARKETING_VERSION = ENV.fetch('SPACEPIN_MARKETING_VERSION', '1.0.0')
CURRENT_PROJECT_VERSION = ENV.fetch('SPACEPIN_BUILD_NUMBER', '1')

def relative_path(path)
  Pathname(path).relative_path_from(ROOT).to_s
end

def sorted_paths(glob)
  Dir.glob(ROOT.join(glob)).sort
end

def add_group_files(group, glob)
  sorted_paths(glob).each do |path|
    group.new_file(File.basename(path))
  end
end

def configure_common_build_settings(target, bundle_id: nil, skip_install: 'NO')
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '6.0'
    config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
    config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
    config.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    config.build_settings['MARKETING_VERSION'] = MARKETING_VERSION
    config.build_settings['CURRENT_PROJECT_VERSION'] = CURRENT_PROJECT_VERSION
    config.build_settings['SKIP_INSTALL'] = skip_install
    config.build_settings['ENABLE_HARDENED_RUNTIME'] = 'YES'
    config.build_settings['CODE_SIGNING_ALLOWED'] = 'YES'
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id if bundle_id
    if DEVELOPMENT_TEAM && !DEVELOPMENT_TEAM.empty?
      config.build_settings['DEVELOPMENT_TEAM'] = DEVELOPMENT_TEAM
    else
      config.build_settings.delete('DEVELOPMENT_TEAM')
    end
  end
end

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH.to_s)
project.root_object.attributes['LastUpgradeCheck'] = '1620'

main_group = project.main_group
sources_group = main_group.new_group('Sources', 'Sources')
spacepin_group = sources_group.new_group('SpacePin', 'SpacePin')
core_group = sources_group.new_group('SpacePinCore', 'SpacePinCore')
tests_group = main_group.new_group('Tests', 'Tests')
core_tests_group = tests_group.new_group('SpacePinCoreTests', 'SpacePinCoreTests')
support_group = main_group.new_group('Support', 'Support')
assets_group = support_group.new_group('Assets.xcassets', 'Assets.xcassets')
resources_group = spacepin_group.new_group('Resources', 'Resources')

app_target = project.new_target(:application, 'SpacePin', :osx, DEPLOYMENT_TARGET)
core_target = project.new_target(:static_library, 'SpacePinCore', :osx, DEPLOYMENT_TARGET)
tests_target = project.new_target(:unit_test_bundle, 'SpacePinCoreTests', :osx, DEPLOYMENT_TARGET)

configure_common_build_settings(app_target, bundle_id: APP_BUNDLE_ID, skip_install: 'NO')
configure_common_build_settings(core_target, bundle_id: "#{APP_BUNDLE_ID}.core", skip_install: 'YES')
configure_common_build_settings(tests_target, bundle_id: "#{APP_BUNDLE_ID}.tests", skip_install: 'YES')

app_target.build_configurations.each do |config|
  config.build_settings['INFOPLIST_FILE'] = 'Support/SpacePin-Info.plist'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Support/SpacePin.entitlements'
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  config.build_settings['ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS'] = 'YES'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/../Frameworks']
end

core_target.build_configurations.each do |config|
  config.build_settings['DEFINES_MODULE'] = 'YES'
  config.build_settings['MACH_O_TYPE'] = 'staticlib'
end

tests_target.build_configurations.each do |config|
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
  config.build_settings['BUNDLE_LOADER'] = ''
  config.build_settings['TEST_HOST'] = ''
end

info_ref = support_group.new_file('SpacePin-Info.plist')
entitlements_ref = support_group.new_file('SpacePin.entitlements')
assets_ref = support_group.new_file('Assets.xcassets')
assets_ref.last_known_file_type = 'folder.assetcatalog'
app_icon_ref = support_group.new_file('AppIcon.icon')
app_icon_ref.last_known_file_type = 'folder'
icns_ref = support_group.new_file('AppIcon.icns')
info_ref.last_known_file_type = 'text.plist.xml'
entitlements_ref.last_known_file_type = 'text.plist.entitlements'

add_group_files(spacepin_group, 'Sources/SpacePin/*.swift')
add_group_files(core_group, 'Sources/SpacePinCore/*.swift')
add_group_files(core_tests_group, 'Tests/SpacePinCoreTests/*.swift')

app_target.add_file_references(spacepin_group.files)
core_target.add_file_references(core_group.files)
tests_target.add_file_references(core_tests_group.files)

localizations_ref = resources_group.new_file('localizations.json')

app_target.resources_build_phase.add_file_reference(assets_ref)
app_target.resources_build_phase.add_file_reference(app_icon_ref)
app_target.resources_build_phase.add_file_reference(icns_ref)
app_target.resources_build_phase.add_file_reference(localizations_ref)
app_target.add_dependency(core_target)
app_target.frameworks_build_phase.add_file_reference(core_target.product_reference)
tests_target.add_dependency(core_target)
tests_target.frameworks_build_phase.add_file_reference(core_target.product_reference)

project.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['SWIFT_VERSION'] = '6.0'
  config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
end

project.save

test_scheme = Xcodeproj::XCScheme.new
test_scheme.configure_with_targets(app_target, tests_target)
test_scheme.save_as(PROJECT_PATH.to_s, 'SpacePinTests', true)
