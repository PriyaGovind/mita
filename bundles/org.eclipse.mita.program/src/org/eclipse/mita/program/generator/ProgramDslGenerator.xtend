/********************************************************************************
 * Copyright (c) 2017, 2018 Bosch Connected Devices and Solutions GmbH.
 *
 * This program and the accompanying materials are made available under the
 * terms of the Eclipse Public License 2.0 which is available at
 * http://www.eclipse.org/legal/epl-2.0.
 *
 * Contributors:
 *    Bosch Connected Devices and Solutions GmbH - initial contribution
 *
 * SPDX-License-Identifier: EPL-2.0
 ********************************************************************************/

/*
 * generated by Xtext 2.10.0
 */
package org.eclipse.mita.program.generator

import com.google.inject.Guice
import com.google.inject.Inject
import com.google.inject.Injector
import com.google.inject.Module
import com.google.inject.Provider
import com.google.inject.name.Named
import java.util.ArrayList
import java.util.List
import org.eclipse.core.resources.IFile
import org.eclipse.core.resources.IProject
import org.eclipse.core.resources.IWorkspaceRoot
import org.eclipse.core.resources.ResourcesPlugin
import org.eclipse.core.runtime.Path
import org.eclipse.emf.common.util.URI
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.resource.Resource
import org.eclipse.emf.ecore.resource.ResourceSet
import org.eclipse.mita.base.scoping.ILibraryProvider
import org.eclipse.mita.base.typesystem.infra.MitaBaseResource
import org.eclipse.mita.base.util.BaseUtils
import org.eclipse.mita.platform.AbstractSystemResource
import org.eclipse.mita.platform.SystemSpecification
import org.eclipse.mita.program.Program
import org.eclipse.mita.program.SystemResourceSetup
import org.eclipse.mita.program.generator.internal.EntryPointGenerator
import org.eclipse.mita.program.generator.internal.ExceptionGenerator
import org.eclipse.mita.program.generator.internal.GeneratedTypeGenerator
import org.eclipse.mita.program.generator.internal.IGeneratorOnResourceSet
import org.eclipse.mita.program.generator.internal.ProgramCopier
import org.eclipse.mita.program.generator.internal.SystemResourceHandlingGenerator
import org.eclipse.mita.program.generator.internal.TimeEventGenerator
import org.eclipse.mita.program.generator.internal.UserCodeFileGenerator
import org.eclipse.mita.program.generator.transformation.ProgramGenerationTransformationPipeline
import org.eclipse.mita.program.model.ModelUtils
import org.eclipse.mita.program.resource.PluginResourceLoader
import org.eclipse.xtext.generator.AbstractGenerator
import org.eclipse.xtext.generator.IFileSystemAccess2
import org.eclipse.xtext.generator.IGeneratorContext
import org.eclipse.xtext.generator.trace.node.CompositeGeneratorNode
import org.eclipse.xtext.resource.XtextResourceSet
import org.eclipse.xtext.service.DefaultRuntimeModule
import org.eclipse.xtext.xbase.lib.Functions.Function1

import static extension org.eclipse.mita.base.util.BaseUtils.force
import static extension org.eclipse.mita.base.util.BaseUtils.castOrNull

/**
 * Generates code from your model files on save.
 * 
 * See https://www.eclipse.org/Xtext/documentation/303_runtime_concepts.html#code-generation
 */
class ProgramDslGenerator extends AbstractGenerator implements IGeneratorOnResourceSet {

	@Inject 
	protected extension ProgramDslTraceExtensions traceExtensions
	
	@Inject
	protected extension ProgramCopier
	
	@Inject
	protected Provider<ProgramGenerationTransformationPipeline> transformer
	
	@Inject
	protected extension GeneratorUtils
	
	@Inject(optional=true)
	protected PlatformBuildSystemGenerator buildSystemGenerator

	@Inject
	protected EntryPointGenerator entryPointGenerator
	
	@Inject
	protected ExceptionGenerator exceptionGenerator
	
	@Inject
	protected GeneratedTypeGenerator generatedTypeGenerator
	
	@Inject
	protected TimeEventGenerator timeEventGenerator
	
	@Inject
	protected SystemResourceHandlingGenerator systemResourceGenerator
	
	@Inject
	protected UserCodeFileGenerator userCodeGenerator
	
	@Inject 
	protected Injector injector
	
	@Inject 
	protected ILibraryProvider libraryProvider
	
	@Inject @Named("injectingModule")
	protected DefaultRuntimeModule injectingModule
	
	@Inject
	protected CompilationContextProvider compilationContextProvider;
	
	@Inject
	protected ModelUtils modelUtils
	
	@Inject
	protected PluginResourceLoader resourceLoader
	
	@Inject
	Provider<XtextResourceSet> resourceSetProvider;
		

	protected def injectPlatformDependencies(Object obj, Module libraryModule) {
		val injector = Guice.createInjector(injectingModule, libraryModule);
		injector.injectMembers(obj)
	}

	override void doGenerate(Resource resource, IFileSystemAccess2 fsa, IGeneratorContext context) {
		resource.resourceSet.doGenerate(fsa);
	}
	
	protected def isMainApplicationFile(Resource resource) {
		return resource.URI.segments.last.startsWith('application.')
	}
	
	private def produceFile(IFileSystemAccess2 fsa, String path, EObject ctx, CompositeGeneratorNode content) {
		var root = CodeFragment.cleanNullChildren(content);
		fsa.generateTracedFile(path, root);
		return path
	}
	
	override doGenerate(ResourceSet input, IFileSystemAccess2 fsa) {
		doGenerate(input, fsa, [ it.URI?.segment(0) == 'resource' ]);
	}
	
	override doGenerate(ResourceSet input, IFileSystemAccess2 fsa, Function1<Resource, Boolean> includeInBuildPredicate) {
		val resourcesToCompile = input
			.resources
			.filter(includeInBuildPredicate)
			.toList();
		
		if(resourcesToCompile.empty) {
			return;
		}
		
		// Include libraries such as the stdlib in the compilation context
		val libs = libraryProvider.standardLibraries;
		val stdlibUri = libs.filter[it.toString.endsWith(MitaBaseResource.PROGRAM_EXT)]
		val stdlib = stdlibUri.map[input.getResource(it, true)].filterNull.map[it.contents.filter(Program).head].force;
		
		val someProgram1 = resourcesToCompile.map[it.contents.head].filter(Program).head;
		val platform = modelUtils.getPlatform(input, someProgram1);
		val platformModule = resourceLoader.loadFromPlugin(platform.eResource, platform.module) as Module;
		injectPlatformDependencies(this, platformModule);
		
		
		/*
		 * Steps:
		 *  1. Copy all programs
		 *  2. Run all programs through pipeline
		 *  3. Collect all sensors, connectivity, exceptions, types
		 *  4. Generate shared files
		 *  5. Generate user code per input model file
		 */
		val copyResourceSet = resourceSetProvider.get();
		val untransformedCompilationContext = compilationContextProvider.get(resourcesToCompile.map[it.contents.head.castOrNull(Program)].filterNull, stdlib);
		val compilationUnits = (resourcesToCompile)
			.map[x | x.contents.filter(Program).head ]
			.filterNull
			.map[x | 
				val resource = x.eResource;	
				if(resource instanceof MitaBaseResource) {	
					if(resource.latestSolution === null) {	
						x.doType();	
					}	
				}
				val copy = x.copy(copyResourceSet);
				BaseUtils.ignoreChange(copy, [
					transformer.get.transform(untransformedCompilationContext, copy)
				]);
				return copy;
			]
			.toList();
		
		val someProgram = compilationUnits.head;
		
		compilationUnits.forEach[
			// some transformation stages might force evaluation of resource descriptions. 
			// Here we clear them again.
			clearCache(it);
		]
		compilationUnits.forEach[
			doType(it);			
		]
		
		var EObject platformRoot = modelUtils.getPlatform(input, compilationUnits.head);
		while(platformRoot.eContainer !== null) {
			platformRoot = platformRoot.eContainer;
		}
		
		doType(platformRoot)
		
		val context = compilationContextProvider.get(compilationUnits, stdlib);
		
		val files = new ArrayList<String>();
		val userTypeFiles = new ArrayList<String>();
		
		// generate all the infrastructure bits
		files += fsa.produceFile('main.c', someProgram, entryPointGenerator.generateMain(context));
		files += fsa.produceFile('base/MitaEvents.h', someProgram, entryPointGenerator.generateEventHeader(context));
		files += fsa.produceFile('base/MitaExceptions.h', someProgram, exceptionGenerator.generateHeader(context));
		
		if (context.hasTimeEvents) {
			files += fsa.produceFile('base/MitaTime.h', someProgram, timeEventGenerator.generateHeader(context));
			files += fsa.produceFile('base/MitaTime.c', someProgram, timeEventGenerator.generateImplementation(context));
		}
		
		for (resourceOrSetup : (context.getResourceGraph().nodes.filter(EObject) + #[platform]).toSet) {
			if(resourceOrSetup instanceof AbstractSystemResource
			|| resourceOrSetup instanceof SystemResourceSetup) { 
				generate(files, fsa, context, resourceOrSetup);
			}
		}
		
		
	
		for (program : compilationUnits.filter[containsCodeRelevantContent]) {
			// generate the actual content for this resource
			files += fsa.produceFile(UserCodeFileGenerator.getResourceBaseName(program) + '.c', program, stdlib.head.trace.append(userCodeGenerator.generateImplementation(context, program)));
			files += fsa.produceFile(UserCodeFileGenerator.getResourceBaseName(program) + '.h', program, stdlib.head.trace.append(userCodeGenerator.generateHeader(context, program)));
			val compilationUnitTypesFilename = UserCodeFileGenerator.getResourceTypesName(program) + '.h';
			files += fsa.produceFile(compilationUnitTypesFilename, program, stdlib.head.trace.append(userCodeGenerator.generateTypes(context, program)));
			userTypeFiles += compilationUnitTypesFilename;
		}
		
		val platformSpec = platform.eContainer as SystemSpecification;
		files += fsa.produceFile(
			UserCodeFileGenerator.getResourceTypesName(platformSpec) + '.h',
			platform, stdlib.head.trace.append(userCodeGenerator.generateTypes(context, platformSpec))
		)
		
		files += fsa.produceFile('base/MitaGeneratedTypes.h', someProgram, generatedTypeGenerator.generateHeader(context, userTypeFiles));
		files += fsa.produceFile('base/MitaGeneratedTypes.c', someProgram, generatedTypeGenerator.generateImplementation(context, userTypeFiles));
		
		files += getUserFiles(input);
		
		buildSystemGenerator?.generateFiles(fsa, context, files)
	}
	
	def generate(List<String> files, IFileSystemAccess2 fsa, CompilationContext context, EObject resourceOrSetup) {
		files += fsa.produceFile('''base/«resourceOrSetup.fileBasename».h''', resourceOrSetup, systemResourceGenerator.generateHeader(context, resourceOrSetup));
		files += fsa.produceFile('''base/«resourceOrSetup.fileBasename».c''', resourceOrSetup, systemResourceGenerator.generateImplementation(context, resourceOrSetup));
		files += systemResourceGenerator.generateAdditionalFiles(fsa, context, resourceOrSetup);
	}
	

	def clearCache(EObject obj) {
		val resource = obj.eResource;
		BaseUtils.getCacheAdapters(resource).forEach[
			it.clearValues();
		];
	}
	
	def doType(EObject program) {
		val resource = program.eResource;
		if(resource instanceof MitaBaseResource) {
			resource.collectAndSolveTypes(program);
		}
	}
	
		
	def Iterable<String> getUserFiles(ResourceSet set) {
        val resource = set.resources.head;   
        val URI uri = resource.URI;
        val projectName = new Path(uri.toPlatformString(true)).segment(0);
        
        val IWorkspaceRoot workspaceRoot = ResourcesPlugin.getWorkspace().getRoot();
        val IProject project = workspaceRoot.getProject(projectName);
        return project
            .members()
            .filter(IFile)
            .map[ it.fullPath.lastSegment ]
            .filter[ it.endsWith(".c") ]
            .map[ "../" + it ];
    }
	
}
