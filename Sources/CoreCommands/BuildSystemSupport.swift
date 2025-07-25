//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Build
import SPMBuildCore
import XCBuildSupport
import SwiftBuildSupport
import PackageGraph
import Workspace

import class Basics.ObservabilityScope
import struct PackageGraph.ModulesGraph
import struct PackageLoading.FileRuleDescription
import protocol TSCBasic.OutputByteStream
import enum PackageModel.TraitConfiguration

private struct NativeBuildSystemFactory: BuildSystemFactory {
    let swiftCommandState: SwiftCommandState

    func makeBuildSystem(
        explicitProduct: String?,
        enableAllTraits: Bool,
        cacheBuildManifest: Bool,
        productsBuildParameters: BuildParameters?,
        toolsBuildParameters: BuildParameters?,
        packageGraphLoader: (() async throws -> ModulesGraph)?,
        outputStream: OutputByteStream?,
        logLevel: Diagnostic.Severity?,
        observabilityScope: ObservabilityScope?,
        delegate: BuildSystemDelegate?
    ) async throws -> any BuildSystem {
        _ = try await swiftCommandState.getRootPackageInformation(enableAllTraits)
        let testEntryPointPath = productsBuildParameters?.testProductStyle.explicitlySpecifiedEntryPointPath
        let cacheBuildManifest = if cacheBuildManifest {
            try await self.swiftCommandState.canUseCachedBuildManifest()
        } else {
            false
        }
        return try BuildOperation(
            productsBuildParameters: try productsBuildParameters ?? self.swiftCommandState.productsBuildParameters,
            toolsBuildParameters: try toolsBuildParameters ?? self.swiftCommandState.toolsBuildParameters,
            cacheBuildManifest: cacheBuildManifest,
            packageGraphLoader: packageGraphLoader ?? {
                try await self.swiftCommandState.loadPackageGraph(
                    explicitProduct: explicitProduct,
                    enableAllTraits: enableAllTraits,
                    testEntryPointPath: testEntryPointPath
                )
            },
            pluginConfiguration: .init(
                scriptRunner: self.swiftCommandState.getPluginScriptRunner(),
                workDirectory: try self.swiftCommandState.getActiveWorkspace().location.pluginWorkingDirectory,
                disableSandbox: self.swiftCommandState.shouldDisableSandbox
            ),
            scratchDirectory: self.swiftCommandState.scratchDirectory,
            traitConfiguration: enableAllTraits ? .enableAllTraits : self.swiftCommandState.traitConfiguration,
            additionalFileRules: FileRuleDescription.swiftpmFileTypes,
            pkgConfigDirectories: self.swiftCommandState.options.locations.pkgConfigDirectories,
            outputStream: outputStream ?? self.swiftCommandState.outputStream,
            logLevel: logLevel ?? self.swiftCommandState.logLevel,
            fileSystem: self.swiftCommandState.fileSystem,
            observabilityScope: observabilityScope ?? self.swiftCommandState.observabilityScope,
            delegate: delegate)
    }
}

private struct XcodeBuildSystemFactory: BuildSystemFactory {
    let swiftCommandState: SwiftCommandState

    func makeBuildSystem(
        explicitProduct: String?,
        enableAllTraits: Bool,
        cacheBuildManifest: Bool,
        productsBuildParameters: BuildParameters?,
        toolsBuildParameters: BuildParameters?,
        packageGraphLoader: (() async throws -> ModulesGraph)?,
        outputStream: OutputByteStream?,
        logLevel: Diagnostic.Severity?,
        observabilityScope: ObservabilityScope?,
        delegate: BuildSystemDelegate?
    ) throws -> any BuildSystem {
        return try XcodeBuildSystem(
            buildParameters: productsBuildParameters ?? self.swiftCommandState.productsBuildParameters,
            packageGraphLoader: packageGraphLoader ?? {
                try await self.swiftCommandState.loadPackageGraph(
                    explicitProduct: explicitProduct,
                    enableAllTraits: enableAllTraits
                )
            },
            outputStream: outputStream ?? self.swiftCommandState.outputStream,
            logLevel: logLevel ?? self.swiftCommandState.logLevel,
            fileSystem: self.swiftCommandState.fileSystem,
            observabilityScope: observabilityScope ?? self.swiftCommandState.observabilityScope,
            delegate: delegate
        )
    }
}

private struct SwiftBuildSystemFactory: BuildSystemFactory {
    let swiftCommandState: SwiftCommandState

    func makeBuildSystem(
        explicitProduct: String?,
        enableAllTraits: Bool,
        cacheBuildManifest: Bool,
        productsBuildParameters: BuildParameters?,
        toolsBuildParameters: BuildParameters?,
        packageGraphLoader: (() async throws -> ModulesGraph)?,
        outputStream: OutputByteStream?,
        logLevel: Diagnostic.Severity?,
        observabilityScope: ObservabilityScope?,
        delegate: BuildSystemDelegate?
    ) throws -> any BuildSystem {
        return try SwiftBuildSystem(
            buildParameters: productsBuildParameters ?? self.swiftCommandState.productsBuildParameters,
            packageGraphLoader: packageGraphLoader ?? {
                try await self.swiftCommandState.loadPackageGraph(
                    explicitProduct: explicitProduct,
                    enableAllTraits: enableAllTraits,
                )
            },
            packageManagerResourcesDirectory: swiftCommandState.packageManagerResourcesDirectory,
            additionalFileRules: FileRuleDescription.swiftpmFileTypes + FileRuleDescription.xcbuildFileTypes,
            outputStream: outputStream ?? self.swiftCommandState.outputStream,
            logLevel: logLevel ?? self.swiftCommandState.logLevel,
            fileSystem: self.swiftCommandState.fileSystem,
            observabilityScope: observabilityScope ?? self.swiftCommandState.observabilityScope,
            pluginConfiguration: .init(
                scriptRunner: self.swiftCommandState.getPluginScriptRunner(),
                workDirectory: try self.swiftCommandState.getActiveWorkspace().location.pluginWorkingDirectory,
                disableSandbox: self.swiftCommandState.shouldDisableSandbox
            ),
            delegate: delegate
        )
    }
}

extension SwiftCommandState {
    public var defaultBuildSystemProvider: BuildSystemProvider {
        .init(providers: [
            .native: NativeBuildSystemFactory(swiftCommandState: self),
            .swiftbuild: SwiftBuildSystemFactory(swiftCommandState: self),
            .xcode: XcodeBuildSystemFactory(swiftCommandState: self)
        ])
    }
}
