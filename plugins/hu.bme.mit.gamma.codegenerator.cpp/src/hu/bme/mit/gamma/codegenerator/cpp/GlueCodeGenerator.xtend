/********************************************************************************
 * Copyright (c) 2018 Contributors to the Gamma project
 *
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *
 * SPDX-License-Identifier: EPL-1.0
 ********************************************************************************/
package hu.bme.mit.gamma.codegenerator.cpp

import hu.bme.mit.gamma.codegenerator.cpp.queries.AbstractSynchronousCompositeComponents
import hu.bme.mit.gamma.codegenerator.cpp.queries.AsynchronousCompositeComponents
import hu.bme.mit.gamma.codegenerator.cpp.queries.Interfaces
import hu.bme.mit.gamma.codegenerator.cpp.queries.SimpleYakinduComponents
import hu.bme.mit.gamma.codegenerator.cpp.queries.SynchronousComponentWrappers
import hu.bme.mit.gamma.statechart.model.Package
import hu.bme.mit.gamma.statechart.model.composite.Component
import java.io.File
import java.io.FileWriter
import java.util.HashSet
import org.eclipse.emf.ecore.resource.ResourceSet
import org.eclipse.viatra.query.runtime.api.IPatternMatch
import org.eclipse.viatra.query.runtime.api.ViatraQueryEngine
import org.eclipse.viatra.query.runtime.api.ViatraQueryMatcher
import org.eclipse.viatra.query.runtime.emf.EMFScope
import org.eclipse.viatra.transformation.runtime.emf.rules.batch.BatchTransformationRule
import org.eclipse.viatra.transformation.runtime.emf.rules.batch.BatchTransformationRuleFactory
import org.eclipse.viatra.transformation.runtime.emf.transformation.batch.BatchTransformation
import org.eclipse.viatra.transformation.runtime.emf.transformation.batch.BatchTransformationStatements

class GlueCodeGenerator {
	// Transformation-related extensions
	extension BatchTransformation transformation 
	extension BatchTransformationStatements statements	
	// Transformation rule-related extensions
	extension BatchTransformationRuleFactory = new BatchTransformationRuleFactory
	// Query engines and resources
	protected final ViatraQueryEngine engine
	protected final ResourceSet resSet
	protected Component topComponent
	// File URIs where the classes need to be saved
	protected final String BASE_PACKAGE_URI
	protected final String CHANNEL_URI
	protected final String INTERFACE_URI
	// The base of the package name, e.g.,: hu.bme.mit.gamma.tutorial.start
	protected final String BASE_PACKAGE_NAME
	// The base of the package name of the generated Yakindu components, not org.yakindu.scr anymore
	protected final String YAKINDU_PACKAGE_NAME
	// Trace
	// Auxiliary transformer objects
	protected final extension TimingDeterminer timingDeterminer = new TimingDeterminer
	protected final extension NameGenerator nameGenerator
	protected final extension EventCodeGenerator eventCodeGenerator
	protected final extension VirtualTimerServiceCodeGenerator virtualTimerServiceCodeGenerator
	protected final extension TimerInterfaceGenerator timerInterfaceGenerator
	protected final extension TimerCallbackInterfaceGenerator timerCallbackInterfaceGenerator
	protected final extension TimerServiceCodeGenerator timerServiceCodeGenerator
	protected final extension PortInterfaceGenerator portInterfaceGenerator
	protected final extension ComponentInterfaceGenerator componentInterfaceGenerator
	protected final extension StatechartWrapperCodeGenerator statechartWrapperCodeGenerator
	protected final extension SynchronousCompositeComponentCodeGenerator synchronousCompositeComponentCodeGenerator
	protected final extension SynchronousComponentWrapperCodeGenerator synchronousComponentWrapperCodeGenerator
	protected final extension ChannelInterfaceGenerator channelInterfaceGenerator
	protected final extension ChannelCodeGenerator channelCodeGenerator
	protected final extension AsynchronousCompositeComponentCodeGenerator asynchronousCompositeComponentCodeGenerator
	
	// Transformation rules
	protected BatchTransformationRule<? extends IPatternMatch, ? extends ViatraQueryMatcher<?>> portInterfaceRule
	protected BatchTransformationRule<? extends IPatternMatch, ? extends ViatraQueryMatcher<?>> simpleComponentsRule
	protected BatchTransformationRule<? extends IPatternMatch, ? extends ViatraQueryMatcher<?>> synchronousCompositeComponentsRule
	protected BatchTransformationRule<? extends IPatternMatch, ? extends ViatraQueryMatcher<?>> synchronousComponentWrapperRule
	protected BatchTransformationRule<? extends IPatternMatch, ? extends ViatraQueryMatcher<?>> channelsRule
	protected BatchTransformationRule<? extends IPatternMatch, ? extends ViatraQueryMatcher<?>> asynchronousCompositeComponentsRule
	
	new(ResourceSet resourceSet, String basePackageName, String srcGenFolderUri) {
		this.BASE_PACKAGE_NAME = basePackageName
		this.YAKINDU_PACKAGE_NAME = basePackageName
		this.resSet = resourceSet
		this.resSet.loadModels
		this.engine = ViatraQueryEngine.on(new EMFScope(resSet))
		this.BASE_PACKAGE_URI = srcGenFolderUri + File.separator + basePackageName.replaceAll("\\.", "/");
		this.CHANNEL_URI = this.BASE_PACKAGE_URI + File.separator + Namings.CHANNEL_PACKAGE_POSTFIX
		this.INTERFACE_URI = this.BASE_PACKAGE_URI + File.separator + Namings.INTERFACE_PACKAGE_POSTFIX
		//
		val trace = new Trace(this.engine)
		this.nameGenerator = new NameGenerator(this.BASE_PACKAGE_NAME)
		this.eventCodeGenerator = new EventCodeGenerator(this.BASE_PACKAGE_NAME)
		this.virtualTimerServiceCodeGenerator = new VirtualTimerServiceCodeGenerator(this.BASE_PACKAGE_NAME)
		this.timerInterfaceGenerator = new TimerInterfaceGenerator(this.BASE_PACKAGE_NAME)
		this.timerCallbackInterfaceGenerator = new TimerCallbackInterfaceGenerator(this.BASE_PACKAGE_NAME)
		this.timerServiceCodeGenerator = new TimerServiceCodeGenerator(this.BASE_PACKAGE_NAME)
		this.portInterfaceGenerator  = new PortInterfaceGenerator(this.BASE_PACKAGE_NAME, trace)
		this.componentInterfaceGenerator = new ComponentInterfaceGenerator(this.BASE_PACKAGE_NAME)
		this.statechartWrapperCodeGenerator = new StatechartWrapperCodeGenerator(this.BASE_PACKAGE_NAME, this.YAKINDU_PACKAGE_NAME, trace)
		this.synchronousCompositeComponentCodeGenerator = new SynchronousCompositeComponentCodeGenerator(this.BASE_PACKAGE_NAME, this.YAKINDU_PACKAGE_NAME, trace)
		this.synchronousComponentWrapperCodeGenerator = new SynchronousComponentWrapperCodeGenerator(this.BASE_PACKAGE_NAME, trace)
		this.channelInterfaceGenerator = new ChannelInterfaceGenerator(this.BASE_PACKAGE_NAME)
		this.channelCodeGenerator = new ChannelCodeGenerator(this.BASE_PACKAGE_NAME)
		this.asynchronousCompositeComponentCodeGenerator = new AsynchronousCompositeComponentCodeGenerator(this.BASE_PACKAGE_NAME, trace)
		setup
	}
	
	/**
	 * Loads the the top component from the resource set. 
	 */
	private def loadModels(ResourceSet resourceSet) {
		for (resource : resourceSet.resources) {
			// To eliminate empty resources
			if (!resource.getContents.empty) {
				if (resource.getContents.get(0) instanceof Package) {
					val gammaPackage = resource.getContents.get(0) as Package
					val components = gammaPackage.components
					if (!components.isEmpty) {
						topComponent = components.head
						return
					}
				}							
			}
		}	
	}
	
	/**
	 * Sets up the transformation infrastructure.
	 */
	protected def setup() {
		//Create VIATRA Batch transformation
		transformation = BatchTransformation.forEngine(engine).build
		//Initialize batch transformation statements
		statements = transformation.transformationStatements
	}

	/**
	 * Executes the code generation.
	 */
	def execute() {
		checkUniqueInterfaceNames
		generateEventClass
		if (topComponent.needTimer) {				
			// Virtual timer is generated only if there are timing specs (triggers) in the model
			generateTimerClasses	
		}	
		getPortInterfaceRule.fireAllCurrent
		getSimpleComponentDeclarationRule.fireAllCurrent
		getSynchronousCompositeComponentsRule.fireAllCurrent
		if (hasSynchronousWrapper) {
			generateLinkedBlockingMultiQueueClasses
		}
		getSynchronousComponentWrapperRule.fireAllCurrent
		if (hasAsynchronousComposite) {
			getChannelsRule.fireAllCurrent
		}
		getAsynchronousCompositeComponentsRule.fireAllCurrent
	}	
	
	/**
	 * Checks whether the ports are connected properly.
	 */
	protected def checkUniqueInterfaceNames() {
		val interfaces = Interfaces.Matcher.on(engine).allValuesOfinterface
		val nameSet = new HashSet<String>
		for (name : interfaces.map[it.name.toLowerCase]) {
			if (nameSet.contains(name)) {
				throw new IllegalArgumentException("Same interface names: " + name + "! Interface names must differ in more than just their initial character!")
			}
			nameSet.add(name)
		}
	}
	
	/**
	 * Returns whether there is a synchronous component wrapper in the model.
	 */
	protected def hasSynchronousWrapper() {
		return SynchronousComponentWrappers.Matcher.on(engine).hasMatch
	}
	
	/**
	 * Returns whether there is a synchronous component wrapper in the model.
	 */
	protected def hasAsynchronousComposite() {
		return AsynchronousCompositeComponents.Matcher.on(engine).hasMatch
	}
		
	/**
	 * Creates and saves the message class that is responsible for informing the statecharts about the event that has to be raised (with the given value).
	 */
	protected def generateEventClass() {
		val componentUri = BASE_PACKAGE_URI + File.separator + eventCodeGenerator.className + ".java"
		val code = eventCodeGenerator.createEventClass
		code.saveCode(componentUri)
	}
	
	/**
	 * Creates and saves the message class that is responsible for informing the statecharts about the event that has to be raised (with the given value).
	 */
	protected def generateTimerClasses() {
		val virtualTimerClassCode = createVirtualTimerClassCode
		virtualTimerClassCode.saveCode(BASE_PACKAGE_URI + File.separator + virtualTimerServiceCodeGenerator.className + ".java")
		val timerInterfaceCode = createITimerInterfaceCode
		timerInterfaceCode.saveCode(BASE_PACKAGE_URI + File.separator + timerInterfaceGenerator.yakinduInterfaceName + ".java")
		val timerCallbackInterface = createITimerCallbackInterfaceCode
		timerCallbackInterface.saveCode(BASE_PACKAGE_URI + File.separator + timerCallbackInterfaceGenerator.interfaceName + ".java")
		val timerServiceClass = createTimerServiceClassCode
		timerServiceClass.saveCode(BASE_PACKAGE_URI + File.separator + timerServiceCodeGenerator.yakinduClassName + ".java")
		val gammaTimerInterface = createGammaTimerInterfaceCode
		gammaTimerInterface.saveCode(BASE_PACKAGE_URI + File.separator + timerInterfaceGenerator.gammaInterfaceName + ".java")
		val gammaTimerClass = createGammaTimerClassCode
		gammaTimerClass.saveCode(BASE_PACKAGE_URI + File.separator + timerServiceCodeGenerator.gammaClassName + ".java")
		val unifiedTimerInterface = createUnifiedTimerInterfaceCode
		unifiedTimerInterface.saveCode(BASE_PACKAGE_URI + File.separator + timerInterfaceGenerator.unifiedInterfaceName + ".java")
		val unifiedTimerClass = createUnifiedTimerClassCode
		unifiedTimerClass.saveCode(BASE_PACKAGE_URI + File.separator + timerServiceCodeGenerator.unifiedClassName + ".java")
	}
	
	/**
	 * Creates a Java interface for each Port Interface.
	 */
	protected def getPortInterfaceRule() {
		if (portInterfaceRule === null) {
			 portInterfaceRule = createRule(Interfaces.instance).action [
				val code = it.interface.generatePortInterfaces
				code.saveCode(BASE_PACKAGE_URI + File.separator + Namings.INTERFACE_PACKAGE_POSTFIX + File.separator + it.interface.generateName + ".java")
			].build		
		}
		return portInterfaceRule
	}
	
	/**
	 * Creates a Java class for each component transformed from Yakindu given in the component model.
	 */
	protected def getSimpleComponentDeclarationRule() {
		if (simpleComponentsRule === null) {
			 simpleComponentsRule = createRule(SimpleYakinduComponents.instance).action [
				val componentUri = BASE_PACKAGE_URI + File.separator  + it.statechartDefinition.containingPackage.name.toLowerCase
				val code = it.statechartDefinition.createSimpleComponentClass
				code.saveCode(componentUri + File.separator + it.statechartDefinition.generateComponentClassName + ".java")
				// Generating the interface for returning the Ports
				val interfaceCode = it.statechartDefinition.generateComponentInterface
				interfaceCode.saveCode(componentUri + File.separator + it.statechartDefinition.generatePortOwnerInterfaceName + ".java")
			].build		
		}
		return simpleComponentsRule
	}
	
	protected def getSynchronousCompositeComponentsRule() {
		if (synchronousCompositeComponentsRule === null) {
			 synchronousCompositeComponentsRule = createRule(AbstractSynchronousCompositeComponents.instance).action [
				val compositeSystemUri = BASE_PACKAGE_URI + File.separator + it.synchronousCompositeComponent.containingPackage.name.toLowerCase
				val code = it.synchronousCompositeComponent.createSynchronousCompositeComponentClass
				code.saveCode(compositeSystemUri + File.separator + it.synchronousCompositeComponent.generateComponentClassName + ".cpp")
				// Generating the interface that is able to return the Ports
				val interfaceCode = it.synchronousCompositeComponent.generateComponentInterface
				interfaceCode.saveCode(compositeSystemUri + File.separator + it.synchronousCompositeComponent.generatePortOwnerInterfaceName + ".h")
			].build		
		}
		return synchronousCompositeComponentsRule
	}
	
	protected def void generateLinkedBlockingMultiQueueClasses() {
		val compositeSystemUri = BASE_PACKAGE_URI.substring(0, BASE_PACKAGE_URI.length - BASE_PACKAGE_NAME.length) + File.separator + "lbmq"
		LinkedBlockingQueueSource.AbstractOfferable.saveCode(compositeSystemUri + File.separator + "AbstractOfferable.java")
		LinkedBlockingQueueSource.AbstractPollable.saveCode(compositeSystemUri + File.separator + "AbstractPollable.java")
		LinkedBlockingQueueSource.LinkedBlockingMultiQueue.saveCode(compositeSystemUri + File.separator + "LinkedBlockingMultiQueue.java")
		LinkedBlockingQueueSource.Offerable.saveCode(compositeSystemUri + File.separator + "Offerable.java")
		LinkedBlockingQueueSource.Pollable.saveCode(compositeSystemUri + File.separator + "Pollable.java")
	}
	
	protected def getSynchronousComponentWrapperRule() {
		if (synchronousComponentWrapperRule === null) {
			 synchronousComponentWrapperRule = createRule(SynchronousComponentWrappers.instance).action [
				val compositeSystemUri = BASE_PACKAGE_URI + File.separator + it.synchronousComponentWrapper.containingPackage.name.toLowerCase
				val code = it.synchronousComponentWrapper.createSynchronousComponentWrapperClass
				code.saveCode(compositeSystemUri + File.separator + it.synchronousComponentWrapper.generateComponentClassName + ".java")
				val interfaceCode = it.synchronousComponentWrapper.generateComponentInterface
				interfaceCode.saveCode(compositeSystemUri + File.separator + it.synchronousComponentWrapper.generatePortOwnerInterfaceName + ".java")
			].build		
		}
		return synchronousComponentWrapperRule
	}
	
	/**
	 * Creates a Java interface for each Port Interface.
	 */
	protected def getChannelsRule() {
		if (channelsRule === null) {
			 channelsRule = createRule(Interfaces.instance).action [
				val channelInterfaceCode = it.interface.createChannelInterfaceCode
				channelInterfaceCode.saveCode(CHANNEL_URI + File.separator + it.interface.generateChannelInterfaceName + ".java")
				val channelClassCode = it.interface.createChannelClassCode
				channelClassCode.saveCode(CHANNEL_URI + File.separator + it.interface.generateChannelName + ".java")	
			].build		
		}
		return channelsRule
	}
	
	protected def getAsynchronousCompositeComponentsRule() {
		if (asynchronousCompositeComponentsRule === null) {
			 asynchronousCompositeComponentsRule = createRule(AsynchronousCompositeComponents.instance).action [
				val compositeSystemUri = BASE_PACKAGE_URI + File.separator + it.asynchronousCompositeComponent.containingPackage.name.toLowerCase
				// Main components
				val code = it.asynchronousCompositeComponent.createAsynchronousCompositeComponentClass(0, 0)
				code.saveCode(compositeSystemUri + File.separator + it.asynchronousCompositeComponent.generateComponentClassName + ".java")
				val interfaceCode = it.asynchronousCompositeComponent.generateComponentInterface
				interfaceCode.saveCode(compositeSystemUri + File.separator + it.asynchronousCompositeComponent.generatePortOwnerInterfaceName + ".java")
			].build		
		}
		return asynchronousCompositeComponentsRule
	}
	
	/**
	 * Creates a Java class from the the given code at the location specified by the given URI.
	 */
	protected def saveCode(CharSequence code, String uri) {
		new File(uri.substring(0, uri.lastIndexOf(File.separator))).mkdirs
		val fw = new FileWriter(uri)
		fw.write(code.toString)
		fw.close
		return 
	}
	
	/**
	 * Disposes of the code generator.
	 */
	def dispose() {
		if (transformation !== null) {
			transformation.dispose
		}
		transformation = null
		return
	}
}
