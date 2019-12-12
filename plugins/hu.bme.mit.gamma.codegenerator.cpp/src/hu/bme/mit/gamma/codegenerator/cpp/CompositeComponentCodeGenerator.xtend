package hu.bme.mit.gamma.codegenerator.cpp

import hu.bme.mit.gamma.statechart.model.composite.AbstractSynchronousCompositeComponent
import hu.bme.mit.gamma.statechart.model.composite.AsynchronousCompositeComponent
import hu.bme.mit.gamma.statechart.model.composite.CascadeCompositeComponent
import hu.bme.mit.gamma.statechart.model.composite.CompositeComponent
import hu.bme.mit.gamma.statechart.model.composite.PortBinding
import hu.bme.mit.gamma.statechart.model.interface_.EventDeclaration
import hu.bme.mit.gamma.statechart.model.interface_.EventDirection
import java.util.Collections

import static extension hu.bme.mit.gamma.statechart.model.derivedfeatures.StatechartModelDerivedFeatures.*

class CompositeComponentCodeGenerator {
	
	final String PACKAGE_NAME
	// 
	final extension TimingDeterminer timingDeterminer = new TimingDeterminer
	final extension ExpressionSerializer expressionSerializer = new ExpressionSerializer
	final extension NameGenerator nameGenerator
	final extension TypeTransformer typeTransformer
	final extension ComponentCodeGenerator componentCodeGenerator
	final extension EventDeclarationHandler gammaEventDeclarationHandler
	//
	final extension Trace trace

	new(String packageName, Trace trace) {
		this.PACKAGE_NAME = packageName
		this.trace = trace
		this.nameGenerator = new NameGenerator(this.PACKAGE_NAME)
		this.typeTransformer = new TypeTransformer(this.trace)
		this.componentCodeGenerator = new ComponentCodeGenerator(this.trace)
		this.gammaEventDeclarationHandler = new EventDeclarationHandler(this.trace)
	}
	
	/**
	 * Generates the needed Java imports in case of the given composite component.
	 */
	protected def generateCompositeSystemImports(CompositeComponent component) '''
		import java.util.List;
		import java.util.LinkedList;
		
		«IF component.needTimer»
			import «PACKAGE_NAME».*;
		«ENDIF»
		import «PACKAGE_NAME».«Namings.INTERFACE_PACKAGE_POSTFIX».*;
		«IF component instanceof AsynchronousCompositeComponent»
			import «PACKAGE_NAME».«Namings.CHANNEL_PACKAGE_POSTFIX».*;
		«ENDIF»
		«FOR containedComponent : component.derivedComponents.map[it.derivedType]
			.filter[!it.generateComponentPackageName.equals(component.generateComponentPackageName)].toSet»
			import «containedComponent.generateComponentPackageName».*;
		«ENDFOR»
	'''
	
	/**
	 * Generates methods that for in-event raisings in case of composite components.
	 */
	def CharSequence delegateRaisingMethods(PortBinding connector) '''
		«FOR event : Collections.singletonList(connector.instancePortReference.port).getSemanticEvents(EventDirection.IN) SEPARATOR "\n"»
			void raise«event.name.toFirstUpper»(«(event.eContainer as EventDeclaration).generateParameter») override {
				parent.«connector.instancePortReference.instance.name».get«connector.instancePortReference.port.name.toFirstUpper»().raise«event.name.toFirstUpper»(«event.parameterDeclarations.head.eventParameterValue»);
			}
		«ENDFOR»
	'''
	
	/**
	 * Generates methods for out-event check delegations in case of composite components.
	 */
	protected def CharSequence delegateOutMethods(PortBinding connector) '''
«««		Simple flag checks
		«FOR event : Collections.singletonList(connector.compositeSystemPort).getSemanticEvents(EventDirection.OUT)»
			@Override
			public boolean isRaised«event.name.toFirstUpper»() {
				return «connector.instancePortReference.instance.name».get«connector.instancePortReference.port.name.toFirstUpper»().isRaised«event.name.toFirstUpper»();
			}
«««		ValueOf checks
			«IF !event.parameterDeclarations.empty»
				@Override
				public «event.toYakinduEvent(connector.compositeSystemPort).type.eventParameterType» get«event.name.toFirstUpper»Value() {
					return «connector.instancePortReference.instance.name».get«connector.instancePortReference.port.name.toFirstUpper»().get«event.name.toFirstUpper»Value();
				}
			«ENDIF»
		«ENDFOR»
	'''
	
	/**
	 * Generates methods for own out-event checks in case of composite components.
	 */
	protected def CharSequence implementOutMethods(PortBinding connector) '''
«««		Simple flag checks
		«FOR event : Collections.singletonList(connector.compositeSystemPort).getSemanticEvents(EventDirection.OUT) SEPARATOR "\n"»
			bool isRaised«event.name.toFirstUpper»() override {
				return mIsRaised«event.name.toFirstUpper»;
			}
«««		ValueOf checks
			«IF !event.parameterDeclarations.empty»
				«event.toYakinduEvent(connector.compositeSystemPort).type.eventParameterType» get«event.name.toFirstUpper»Value() override {
					return «event.name.toFirstLower»Value;
				}
			«ENDIF»
		«ENDFOR»
	'''
	
	/** Sets the parameters of the component and instantiates the necessary components with them. */
	def createInstances(CompositeComponent component) '''
		«FOR parameter : component.parameterDeclarations SEPARATOR ", "»
			this->«parameter.name» = «parameter.name»;
		«ENDFOR»
	'''
	
	/** Sets the parameters of the component and instantiates the necessary components with them. */
	def createInitList(CompositeComponent component) '''
		«FOR instance : component.derivedComponents SEPARATOR ", "»
			«instance.name»(«instance.derivedType.generateComponentClassName»(«FOR argument : instance.arguments SEPARATOR ", "»«argument.serialize»«ENDFOR»))
		«ENDFOR»
		««« Coma after component instances (if necesary)
«IF component.derivedComponents.size != 0 && component.portBindings.map[it.compositeSystemPort].size != 0 »,«ENDIF»
		««« Coma before port initializations (if necesary)
		«FOR port : component.portBindings.map[it.compositeSystemPort] SEPARATOR ", "»
			«port.name.toFirstLower»(*this)
		«ENDFOR»
	'''
	
	/**
	 * Returns the instances (in order) that should be scheduled in the given AbstractSynchronousCompositeComponent.
	 * Note that in casacade composite an instance might be scheduled multiple times.
	 */
	dispatch def getInstancesToBeScheduled(AbstractSynchronousCompositeComponent component) {
		return component.components
	}
	
	dispatch def getInstancesToBeScheduled(CascadeCompositeComponent component) {
		if (component.executionList.empty) {
			return component.components
		}
		return component.executionList
	}
	
}