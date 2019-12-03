package hu.bme.mit.gamma.codegenerator.cpp

import hu.bme.mit.gamma.codegenerator.cpp.queries.BroadcastChannels
import hu.bme.mit.gamma.codegenerator.cpp.queries.SimpleChannels
import hu.bme.mit.gamma.statechart.model.StatechartDefinition
import hu.bme.mit.gamma.statechart.model.composite.AbstractSynchronousCompositeComponent
import hu.bme.mit.gamma.statechart.model.composite.CascadeCompositeComponent
import hu.bme.mit.gamma.statechart.model.composite.SynchronousCompositeComponent
import hu.bme.mit.gamma.statechart.model.interface_.EventDeclaration
import hu.bme.mit.gamma.statechart.model.interface_.EventDirection
import java.util.Collections
import hu.bme.mit.gamma.statechart.model.composite.CompositeComponent

class SynchronousCompositeComponentCodeGenerator {
	
	final String PACKAGE_NAME
	// 
	final extension TimingDeterminer timingDeterminer = new TimingDeterminer
	final extension Trace trace
	final extension NameGenerator nameGenerator
	final extension TypeTransformer typeTransformer
	final extension EventDeclarationHandler gammaEventDeclarationHandler
	final extension ComponentCodeGenerator componentCodeGenerator
	final extension CompositeComponentCodeGenerator compositeComponentCodeGenerator
	//
	final String INSERT_QUEUE = "insertQueue"
	final String EVENT_QUEUE = "eventQueue"

	new(String packageName, String yakinduPackageName, Trace trace) {
		this.PACKAGE_NAME = packageName
		this.trace = trace
		this.nameGenerator = new NameGenerator(this.PACKAGE_NAME)
		this.typeTransformer = new TypeTransformer(trace)
		this.gammaEventDeclarationHandler = new EventDeclarationHandler(this.trace)
		this.componentCodeGenerator = new ComponentCodeGenerator(this.trace)
		this.compositeComponentCodeGenerator = new CompositeComponentCodeGenerator(this.PACKAGE_NAME, this.trace)
	}
	
	/**
	* Creates the C++ code of the synchronous composite class, containing the statemachine instances.
	*/
	protected def createSynchronousCompositeComponentClass(AbstractSynchronousCompositeComponent component) '''
		//package «component.generateComponentPackageName»;
		/*
		«component.generateCompositeSystemImports»
		*/
	    #include <functional>
	    #include <vector>
	    #include "../OneThreadedTimer.cpp"
	    
	    #include "./«component.generateComponentClassName»Interface.h"
	    
	    «var list = newArrayList()»
		«FOR instance : component.components»
			«IF !list.contains(instance.type.containingPackage.getName.toLowerCase)»
				#include "../«instance.type.containingPackage.getName.toLowerCase»/«instance.type.generateComponentClassName».cpp"
				«IF list.add(instance.type.containingPackage.getName.toLowerCase)» «««supress output
				«ENDIF»
			«ENDIF»
		«ENDFOR»
	
		//SynchronousCompositeComponentCode
		class «component.generateComponentClassName» : public «component.generatePortOwnerInterfaceName» {
			// Component instances
			«FOR instance : component.components»
				«instance.type.generateComponentClassName» «instance.name»;
			«ENDFOR»

		  public:
		  		////////////////////
			// Inner classes representing Ports
			«FOR portBinding : component.portBindings SEPARATOR "\n"»
				class «portBinding.compositeSystemPort.name.toFirstUpper» : public «portBinding.compositeSystemPort.interfaceRealization.interface.generateName»::«portBinding.compositeSystemPort.interfaceRealization.realizationMode.toString.toLowerCase.toFirstUpper» {
					std::vector<std::reference_wrapper<«portBinding.compositeSystemPort.interfaceRealization.interface.generateName»::Listener::«portBinding.compositeSystemPort.interfaceRealization.realizationMode.toString.toLowerCase.toFirstUpper»>> listeners;
					«component.generateComponentClassName»& parent;
					
					//Cascade components need their raised events saved (multiple schedule of a component in a single turn)
					«FOR event : Collections.singletonList(portBinding.compositeSystemPort).getSemanticEvents(EventDirection.OUT)»
						bool mIsRaised«event.name.toFirstUpper» = false;
						«IF !event.parameterDeclarations.empty»
							«event.toYakinduEvent(portBinding.compositeSystemPort).type.eventParameterType» «event.name.toFirstLower»Value;
						«ENDIF»
					«ENDFOR»
					
					// Class for the setting of the boolean fields (events)
					class «portBinding.compositeSystemPort.name.toFirstUpper»Util : public «portBinding.compositeSystemPort.interfaceRealization.interface.generateName»::Listener::«portBinding.compositeSystemPort.interfaceRealization.realizationMode.toString.toLowerCase.toFirstUpper» {
					  «portBinding.compositeSystemPort.name.toFirstUpper»& parent;
					  public:
					  	«portBinding.compositeSystemPort.name.toFirstUpper»Util(«portBinding.compositeSystemPort.name.toFirstUpper»& parent_) : parent(parent_) {  }
						«FOR event : Collections.singletonList(portBinding.compositeSystemPort).getSemanticEvents(EventDirection.OUT) SEPARATOR "\n"»
							
							void raise«event.name.toFirstUpper»(«(event.eContainer as EventDeclaration).generateParameter») override {
								parent.mIsRaised«event.name.toFirstUpper» = true;
								«IF !event.parameterDeclarations.empty»
										parent.«event.name.toFirstLower»Value = «event.parameterDeclarations.head.eventParameterValue»;
								«ENDIF»
							}
						«ENDFOR»
					};
				  public:
					«portBinding.compositeSystemPort.name.toFirstUpper»(«component.generateComponentClassName»& parent_) : parent(parent_) {
						// Registering the listener to the contained component
						«portBinding.compositeSystemPort.name.toFirstUpper»Util util(*this);
						parent.«portBinding.instancePortReference.instance.name».get«portBinding.instancePortReference.port.name.toFirstUpper»().registerListener(util);
					}
					
					«portBinding.delegateRaisingMethods»
					
					«portBinding.implementOutMethods»
					
					
					void registerListener(«portBinding.compositeSystemPort.interfaceRealization.interface.generateName»::Listener::«portBinding.compositeSystemPort.interfaceRealization.realizationMode.toString.toLowerCase.toFirstUpper»& listener) override {
						listeners.push_back(listener);
					}
					
					std::vector<std::reference_wrapper<«portBinding.compositeSystemPort.interfaceRealization.interface.generateName»::Listener::«portBinding.compositeSystemPort.interfaceRealization.realizationMode.toString.toLowerCase.toFirstUpper»>> getRegisteredListeners() override {
						return listeners;
					}
					
					/** Resetting the boolean event flags to false. */
					void clear() {
						«FOR event : Collections.singletonList(portBinding.compositeSystemPort).getSemanticEvents(EventDirection.OUT)»
							mIsRaised«event.name.toFirstUpper» = false;
						«ENDFOR»
					}
					
					/** Notifying the registered listeners. */
					void notifyListeners() {
						«FOR event : Collections.singletonList(portBinding.compositeSystemPort).getSemanticEvents(EventDirection.OUT)»
							if (mIsRaised«event.name.toFirstUpper») {
								for (auto listener : listeners) {
									listener.get().raise«event.name.toFirstUpper»(«IF !event.parameterDeclarations.empty»«event.name.toFirstLower»Value«ENDIF»);
								}
							}
						«ENDFOR»
					}
					
				};
				
				«portBinding.compositeSystemPort.name.toFirstUpper»& get«portBinding.compositeSystemPort.name.toFirstUpper»() override {
					return «portBinding.compositeSystemPort.name.toFirstLower»;
				}
			«ENDFOR»

		  		////////////////////
		  private:
	  			// Port instances
	  			«FOR port : component.portBindings.map[it.compositeSystemPort]»
	  				«port.name.toFirstUpper» «port.name.toFirstLower»;
	  			«ENDFOR»
	  			«component.generateParameterDeclarationFields»
		  public:
		  /*
			«IF component.needTimer»
				«component.generateComponentClassName»(«FOR parameter : component.parameterDeclarations SEPARATOR ", " AFTER ", "»«parameter.type.transformType» «parameter.name»«ENDFOR»«Namings.UNIFIED_TIMER_INTERFACE» timer) {
					«component.createInstances»
					setTimer(timer);
					init();
				}
			«ENDIF»
			*/
			«component.generateComponentClassName»(«FOR parameter : component.parameterDeclarations SEPARATOR ", "»«parameter.type.transformType» «parameter.name»«ENDFOR») :
				«component.createInitList» {
				
				«component.createInstances»
				init();
			}
			
			/** Resets the contained statemachines recursively. Must be called to initialize the component. */
			
			void reset() override {
				«FOR instance : component.components»
					«instance.name».reset();
				«ENDFOR»								
				// Initializing chain of listeners and events 
				initListenerChain();
			}
		  private:
			/** Creates the channel mappings and enters the wrapped statemachines. */
			void init() {
				// Registration of simple channels
				«FOR channelMatch : SimpleChannels.Matcher.on(engine).getAllMatches(component, null, null, null)»
					«channelMatch.providedPort.instance.name».get«channelMatch.providedPort.port.name.toFirstUpper»().registerListener(«channelMatch.requiredPort.instance.name».get«channelMatch.requiredPort.port.name.toFirstUpper»());
					«channelMatch.requiredPort.instance.name».get«channelMatch.requiredPort.port.name.toFirstUpper»().registerListener(«channelMatch.providedPort.instance.name».get«channelMatch.providedPort.port.name.toFirstUpper»());
				«ENDFOR»
				// Registration of broadcast channels
				«FOR channelMatch : BroadcastChannels.Matcher.on(engine).getAllMatches(component, null, null, null)»
					«channelMatch.providedPort.instance.name».get«channelMatch.providedPort.port.name.toFirstUpper»().registerListener(«channelMatch.requiredPort.instance.name».get«channelMatch.requiredPort.port.name.toFirstUpper»());
				«ENDFOR»
				«IF component instanceof CascadeCompositeComponent»
					// Setting only a single queue for cascade statecharts
					«FOR instance : component.components.filter[it.type instanceof StatechartDefinition]»
						«instance.name».change«INSERT_QUEUE.toFirstUpper»();
					«ENDFOR»
				«ENDIF»
			}

			/** Clears the the boolean flags of all out-events in each contained port. */
			void clearPorts() {
				«FOR portBinding : component.portBindings»
					get«portBinding.compositeSystemPort.name.toFirstUpper»().clear();
				«ENDFOR»
			}
			
			/** Notifies all registered listeners in each contained port. */
			void notifyListeners() {
				«FOR portBinding : component.portBindings»
					get«portBinding.compositeSystemPort.name.toFirstUpper»().notifyListeners();
				«ENDFOR»
			}
		  public:
			/** Needed for the right event notification after initialization, as event notification from contained components
			 * does not happen automatically (see the port implementations and runComponent method). */
			void initListenerChain() {
				«FOR instance : component.components.filter[!(it.type instanceof StatechartDefinition)]»
					«instance.name».initListenerChain();
				«ENDFOR»
				notifyListeners();
			}
			
			«IF component instanceof SynchronousCompositeComponent»
				/** Changes the event and process queues of all component instances. Should be used only be the container (composite system) class. */
				void change«EVENT_QUEUE.toFirstUpper»s() {
					«FOR instance : component.components.filter[!(it.type instanceof CascadeCompositeComponent)]»
						«instance.name».change«EVENT_QUEUE.toFirstUpper»s();
					«ENDFOR»
				}
			«ENDIF»
			
			/** Returns whether all event queues of the contained component instances are empty. 
			Should be used only be the container (composite system) class. */
			bool is«EVENT_QUEUE.toFirstUpper»Empty() {
				return «FOR instance : component.components SEPARATOR " && "»«instance.name».is«EVENT_QUEUE.toFirstUpper»Empty()«ENDFOR»;
			}
			
			/** Initiates cycle runs until all event queues of component instances are empty. */
			
			void runFullCycle() override {
				do {
					runCycle();
				}
				while (!is«EVENT_QUEUE.toFirstUpper»Empty());
			}
			
			/** Changes event queues and initiates a cycle run.
				This should be the execution point from an asynchronous component. */
			
			void runCycle() override {
				«IF component instanceof SynchronousCompositeComponent»
					// Changing the insert and process queues for all synchronous subcomponents
					change«EVENT_QUEUE.toFirstUpper»s();
				«ENDIF»
				// Composite type-dependent behavior
				runComponent();
			}
			
			/** Initiates a cycle run without changing the event queues.
			 * Should be used only be the container (composite system) class. */
			void runComponent() {
				// Starts with the clearing of the previous out-event flags
				clearPorts();
				// Running contained components
				«FOR instance : component.instancesToBeScheduled»
					«IF component instanceof CascadeCompositeComponent && instance.type instanceof SynchronousCompositeComponent»
						«instance.name».runCycle();
					«ELSE»
						«instance.name».runComponent();
					«ENDIF»
				«ENDFOR»
				// Notifying registered listeners
				notifyListeners();
			}
	
			«IF component.needTimer»
				/** Setter for the timer e.g., a virtual timer. */
				//«Namings.UNIFIED_TIMER_INTERFACE»
				void setTimer(OneThreadTimer timer) {
					«FOR instance : component.components»
						«IF instance.type.needTimer»
							«instance.name».setTimer(timer);
						«ENDIF»
					«ENDFOR»
				}
			«ENDIF»
			
			/**  Getter for component instances, e.g., enabling to check their states. */
			«FOR instance : component.components SEPARATOR "\n"»
				«instance.type.generateComponentClassName»& get«instance.name.toFirstUpper»() {
					return «instance.name»;
				}
			«ENDFOR»
			
		};
	'''
	
}