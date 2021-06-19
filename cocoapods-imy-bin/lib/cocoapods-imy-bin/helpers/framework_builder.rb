# copy from https://github.com/CocoaPods/cocoapods-packager

require 'cocoapods-imy-bin/helpers/framework.rb'
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
        defines = compile
        build_sim_framework(defines)

        defines
      end

      def output_xcframework(defines)
        UI.section("Building static Library #{@spec}") do
          build_xcframework_for_ios(xcframeworkPath)
        end
        Pathname(@platform.name.to_s)
      end

      private

      def build_sim_framework(defines)
        UI.message 'Building simulator libraries'
        xcodebuild(defines, "-destination=\"iOS\" -sdk iphonesimulator ", "build-iphonesimulator",@build_model)
      end

      def build_xcframework_for_ios(output)
        UI.message "Building ios libraries with archs #{ios_architectures}"
        rootPath = File.join(File.expand_path("..", output), File.basename(output))
        build_path = Pathname("build")
        build_path.mkpath unless build_path.exist?

        libs = [ios_architectures, ios_architectures_sim].map do |arch|
          library = "build-#{arch}/#{@spec.name}.framework"
          library
        end

        frameworks = libs.map do | lib |
          "-framework #{File.join(File.expand_path("..", lib), File.basename(lib))}"
        end

        command = "xcodebuild -create-xcframework #{frameworks.join(' ')} -output #{rootPath}"
        UI.message "command = #{command}"
        `#{command}`
      end

      def ios_architectures
        archs = "iphoneos"
        archs
      end

      def ios_architectures_sim
        archs = "iphonesimulator"
        archs
      end

      def compile
        defines = "GCC_PREPROCESSOR_DEFINITIONS='$(inherited)'"
        defines += ' '
        defines += @spec.consumer(@platform).compiler_flags.join(' ')

        xcodebuild(defines, "-destination=\"iOS\" -sdk iphoneos OTHER_CFLAGS=\"-fembed-bitcode -Qunused-arguments\"","build-#{ios_architectures}",@build_model)

        defines
      end

      def target_name
        #区分多平台，如配置了多平台，会带上平台的名字
        # 如libwebp-iOS
        if @spec.available_platforms.count > 1
          "#{@spec.name}-#{Platform.string_name(@spec.consumer(@platform).platform_name)}"
        else
          @spec.name
        end
      end

      def xcodebuild(defines = '', args = '', build_dir = 'build', build_model = 'Debug')
        command = "
        xcodebuild archive \
        #{defines} #{args} \
        CONFIGURATION_BUILD_DIR=#{File.join(File.expand_path("..", build_dir), File.basename(build_dir))} \
        clean build \
        -configuration #{build_model} \
        -target #{target_name} -project ./Pods/Pods.xcodeproj \
        SKIP_INSTALL=NO \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
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
        return Pathname.new(@platform.name.to_s) + "#{@spec.name}.xcframework"
      end

    end
  end
end
