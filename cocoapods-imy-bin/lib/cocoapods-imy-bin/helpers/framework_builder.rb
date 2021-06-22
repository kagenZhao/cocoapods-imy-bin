# copy from https://github.com/CocoaPods/cocoapods-packager


require 'English'
require 'cocoapods-imy-bin/config/config_builder'
require 'shellwords'

module CBin
  class Framework
    class Builder
      include Pod
      #Debug下还待完成
      def initialize(spec, file_accessor, platform, source_dir, isRootSpec = true, build_model="Release")
        @spec = spec
        @source_dir = source_dir
        @file_accessor = file_accessor
        @platform = platform
        @build_model = build_model
        @isRootSpec = isRootSpec
        #vendored_static_frameworks 只有 xx.framework  需要拼接为 xx.framework/xx by slj
        vendored_static_frameworks = file_accessor.vendored_static_frameworks.map do |framework|
          path = framework
          extn = File.extname  path
          if extn.downcase == '.framework'
            path = File.join(path,File.basename(path, extn))
          end
          path
        end

        @vendored_libraries = (vendored_static_frameworks + file_accessor.vendored_static_libraries).map(&:to_s)
      end

      def build
        buildOS
        buildSimulator
      end

      def output_xcframework()
        UI.section("Building XCFramework #{@spec}") do
          build_xcframework_for_ios(xcframeworkPath)
        end
        Pathname(@platform.name.to_s)
      end

      private

      def build_xcframework_for_ios(output)
        rootPath = File.join(File.expand_path("..", output), File.basename(output))
        build_path = Pathname("build")
        build_path.mkpath unless build_path.exist?

        libs = %w[iphoneos iphonesimulator].map do |arch|
          library = "build-#{arch}/#{project_name}.framework"
          library
        end

        frameworks = libs.map do | lib |
          "-framework #{File.join(File.expand_path("..", lib), File.basename(lib))}"
        end

        command = "xcodebuild -create-xcframework -allow-internal-distribution #{frameworks.join(' ')} -output #{rootPath}"
        UI.message "command = #{command}"
        `#{command}`
      end

      def defines
        arg_defines = "GCC_PREPROCESSOR_DEFINITIONS='$(inherited)'"
        arg_defines += ""
        arg_defines += @spec.consumer(@platform).compiler_flags.join(' ')
        arg_defines
      end

      def buildOS
        xcodebuild('-sdk iphoneos', 'build-iphoneos')
      end

      def buildSimulator
        xcodebuild('-sdk iphonesimulator ONLY_ACTIVE_ARCH=NO', 'build-iphonesimulator')
      end

      def project_name
        if @project_name
          @project_name
        else
          command = "xcodebuild -target #{target_name} -project ./Pods/Pods.xcodeproj -configuration #{@build_model} -showBuildSettings  | grep -i ' PRODUCT_NAME' "
          output = `#{command}`.to_s
          if $CHILD_STATUS.exitstatus != 0
            @spec.name
          else
            matched = output.match(/PRODUCT_NAME\s?=\s?(.*?)$/)
            @project_name = matched[1]
            CBin::Config::Builder.instance.set_project_name(@spec, @project_name)
            @project_name
          end
        end
      end

      def target_name
        #区分多平台，如配置了多平台，会带上平台的名字
        # 如libwebp-iOS
        unless @isRootSpec
          @spec.name
        else
          if @spec.available_platforms.count > 1
            "#{@spec.name}-#{Platform.string_name(@spec.consumer(@platform).platform_name)}"
          else
            @spec.name
          end
        end
      end

      def xcodebuild(args = '', build_dir)
        command = "
        xcodebuild build \\
        #{defines} #{args} \\
        CONFIGURATION_BUILD_DIR=#{File.join(File.expand_path("..", build_dir), File.basename(build_dir))} \\
        -configuration #{@build_model} \\
        -target #{target_name} \\
        -project ./Pods/Pods.xcodeproj \\
        DEBUG_INFORMATION_FORMAT='dwarf' \\
        SKIP_INSTALL=NO \\
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \\
        2>&1
        "

        UI.message "command = #{command}"
        output = `#{command}`.lines.to_a

        if $CHILD_STATUS.exitstatus != 0
          raise <<~EOF
            Build command failed: #{command}
            Output:
            #{output.map { |line| "    #{line}" }.join}
          EOF

          Process.exit
        end
      end

      def expand_paths(source_dir, path_specs)
        path_specs.map do |path_spec|
          Dir.glob(File.join(source_dir, path_spec))
        end
      end

      def xcframeworkPath
        return Pathname.new(@platform.name.to_s) + "#{project_name}.xcframework"
      end

    end
  end
end
