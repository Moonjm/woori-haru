#!/usr/bin/env ruby
# frozen_string_literal: true

# WooriHaru 앱 타겟에 Swift 파일을 등록한다.
#
# **왜 필요한가.** 이 프로젝트에서 폴더 동기화(`PBXFileSystemSynchronizedRootGroup`)가
# 걸린 곳은 `WooriHaruTests`와 `StudyTimerWidget` 뿐이다. 앱 타겟(`WooriHaru`)은
# `PBXSourcesBuildPhase`에 파일을 하나씩 등록하는 전통 방식이라, `WooriHaru/` 아래에
# 파일을 만들어 두기만 하면 **컴파일 대상에 잡히지 않는다.** 테스트 파일은 자동으로
# 잡히므로 「테스트는 컴파일되는데 본 코드가 없다」는 형태로 드러난다.
#
# 사용:
#   ruby scripts/xcode-add-files.rb WooriHaru/Models/Foo.swift WooriHaru/Services/Bar.swift
#
# 이미 등록된 파일은 건너뛴다(여러 번 돌려도 안전하다).
# `xcodeproj` gem이 필요하다: gem install --user-install xcodeproj

require 'xcodeproj'

PROJECT_PATH = 'WooriHaru.xcodeproj'
TARGET_NAME = 'WooriHaru'

paths = ARGV
if paths.empty?
  warn 'usage: ruby scripts/xcode-add-files.rb <path.swift> [...]'
  exit 1
end

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.find { |t| t.name == TARGET_NAME }
abort "타겟을 찾지 못했다: #{TARGET_NAME}" if target.nil?

# 이미 빌드에 들어 있는 파일 경로 모음. 중복 등록은 빌드를 깨뜨린다.
# `filter_map`은 Ruby 2.7+다. macOS 시스템 ruby(2.6)에서도 돌도록 map+compact를 쓴다.
existing = target.source_build_phase.files.map { |f| f.file_ref && f.file_ref.real_path.to_s }.compact

added = []
skipped = []

paths.each do |path|
  abs = File.expand_path(path)
  abort "파일이 없다: #{path}" unless File.exist?(abs)

  if existing.include?(abs)
    skipped << path
    next
  end

  # 디렉터리 구조를 그대로 그룹으로 만든다 — Xcode 네비게이터가 파일 시스템과 어긋나면
  # 다음 사람이 파일을 찾지 못한다.
  group = project.main_group
  File.dirname(path).split('/').each do |segment|
    group = group.find_subpath(segment, true)
    group.set_source_tree('SOURCE_ROOT') if group.source_tree.nil?
  end

  file_ref = group.new_reference(abs)
  target.add_file_references([file_ref])
  added << path
end

project.save

puts "등록: #{added.empty? ? '없음' : added.join(', ')}"
puts "건너뜀(이미 등록됨): #{skipped.join(', ')}" unless skipped.empty?
