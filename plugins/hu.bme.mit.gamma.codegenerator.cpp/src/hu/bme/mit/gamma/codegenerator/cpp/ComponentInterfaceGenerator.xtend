package hu.bme.mit.gamma.codegenerator.cpp

import hu.bme.mit.gamma.statechart.model.Port
import hu.bme.mit.gamma.statechart.model.composite.AbstractSynchronousCompositeComponent
import hu.bme.mit.gamma.statechart.model.composite.AsynchronousAdapter
import hu.bme.mit.gamma.statechart.model.composite.AsynchronousComponent
import hu.bme.mit.gamma.statechart.model.composite.Component
import hu.bme.mit.gamma.statechart.model.composite.CompositeComponent
import hu.bme.mit.gamma.statechart.model.composite.SynchronousComponent
import java.util.HashSet

import static extension hu.bme.mit.gamma.statechart.model.derivedfeatures.StatechartModelDerivedFeatures.*

class ComponentInterfaceGenerator {
	
	final String PACKAGE_NAME
	//
	final extension NameGenerator nameGenerator
	
	new(String packageName) {
		this.PACKAGE_NAME = packageName
		this.nameGenerator = new NameGenerator(this.PACKAGE_NAME)
	}
	
	/**
	 * Generates the Java interface code (implemented by the component) of the given component.
	 */
	protected def generateComponentInterface(Component component) {
		var ports = new HashSet<Port>
		if (component instanceof CompositeComponent) {
			val composite = component as CompositeComponent
			// Only bound ports are created
			ports += composite.portBindings.map[it.compositeSystemPort]
		}
		else if (component instanceof AsynchronousAdapter) {
			ports += component.allPorts
		}
		else {
			ports += component.ports
		}
		val interfaceCode = '''
			//package «component.generateComponentPackageName»;
			
			#ifndef «component.generatePortOwnerInterfaceName.toUpperCase»
			#define «component.generatePortOwnerInterfaceName.toUpperCase»
			
			«var list = newArrayList()»
			«FOR interfaceName : ports.map[it.interfaceRealization.interface.generateName].toSet»
				«IF !list.contains(interfaceName)»
					#include "../interfaces/«interfaceName».h"
					«IF list.add(interfaceName)» «««supress output
					«ENDIF»
				«ENDIF»
			«ENDFOR»
			
			//ComponentInterfaceGenerator
			class «component.generatePortOwnerInterfaceName» {
			  public:
				«FOR port : ports»
					virtual «port.implementedCppInterfaceName»& get«port.name.toFirstUpper»() = 0;
				«ENDFOR»
				
				virtual void reset() = 0;
				
				«IF component instanceof SynchronousComponent»virtual void runCycle() = 0;«ENDIF»
				«IF component instanceof AbstractSynchronousCompositeComponent»virtual void runFullCycle() = 0;«ENDIF»
				«IF component instanceof AsynchronousComponent»virtual void start() = 0;«ENDIF»
			
			};
			
			#endif
		'''
		return interfaceCode
	}
}