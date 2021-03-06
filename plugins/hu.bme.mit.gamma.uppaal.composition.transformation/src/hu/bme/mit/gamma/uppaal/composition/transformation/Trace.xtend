package hu.bme.mit.gamma.uppaal.composition.transformation

import hu.bme.mit.gamma.statechart.model.Clock
import hu.bme.mit.gamma.statechart.model.EntryState
import hu.bme.mit.gamma.statechart.model.Port
import hu.bme.mit.gamma.statechart.model.State
import hu.bme.mit.gamma.statechart.model.StateNode
import hu.bme.mit.gamma.statechart.model.composite.AsynchronousAdapter
import hu.bme.mit.gamma.statechart.model.composite.AsynchronousComponentInstance
import hu.bme.mit.gamma.statechart.model.composite.ComponentInstance
import hu.bme.mit.gamma.statechart.model.composite.MessageQueue
import hu.bme.mit.gamma.statechart.model.interface_.Event
import hu.bme.mit.gamma.statechart.model.interface_.EventDirection
import hu.bme.mit.gamma.uppaal.transformation.queries.ClockRepresentations
import hu.bme.mit.gamma.uppaal.transformation.queries.EventRepresentations
import hu.bme.mit.gamma.uppaal.transformation.queries.ExpressionTraces
import hu.bme.mit.gamma.uppaal.transformation.queries.InstanceTraces
import hu.bme.mit.gamma.uppaal.transformation.queries.MessageQueueTraces
import hu.bme.mit.gamma.uppaal.transformation.queries.PortTraces
import hu.bme.mit.gamma.uppaal.transformation.queries.Traces
import hu.bme.mit.gamma.uppaal.transformation.traceability.AbstractTrace
import hu.bme.mit.gamma.uppaal.transformation.traceability.ExpressionTrace
import hu.bme.mit.gamma.uppaal.transformation.traceability.G2UTrace
import hu.bme.mit.gamma.uppaal.transformation.traceability.InstanceTrace
import hu.bme.mit.gamma.uppaal.transformation.traceability.MessageQueueTrace
import hu.bme.mit.gamma.uppaal.transformation.traceability.TraceabilityPackage
import java.util.Collections
import java.util.HashSet
import java.util.List
import java.util.Set
import org.eclipse.emf.ecore.EClass
import org.eclipse.emf.ecore.EObject
import org.eclipse.viatra.query.runtime.api.ViatraQueryEngine
import org.eclipse.viatra.query.runtime.emf.EMFScope
import org.eclipse.viatra.transformation.runtime.emf.modelmanipulation.IModelManipulations
import uppaal.declarations.ChannelVariableDeclaration
import uppaal.declarations.DataVariableDeclaration
import uppaal.declarations.DataVariablePrefix
import uppaal.declarations.FunctionDeclaration
import uppaal.declarations.VariableDeclaration
import uppaal.expressions.BinaryExpression
import uppaal.expressions.IdentifierExpression
import uppaal.expressions.LiteralExpression
import uppaal.expressions.MinusExpression
import uppaal.expressions.NegationExpression
import uppaal.expressions.PlusExpression
import uppaal.templates.Edge
import uppaal.templates.Location
import uppaal.templates.LocationKind
import uppaal.templates.Synchronization

import static extension hu.bme.mit.gamma.statechart.model.derivedfeatures.StatechartModelDerivedFeatures.*
import static extension hu.bme.mit.gamma.uppaal.composition.transformation.Namings.*

class Trace {
	// EMF Trace model and engine
	protected final ViatraQueryEngine traceEngine
	protected final G2UTrace traceRoot
	// Model manipulation
	final extension IModelManipulations manipulation	
	// Factories
	final extension TraceabilityPackage trPackage = TraceabilityPackage.eINSTANCE
	// Auxiliary objects 
	final extension EventHandler eventHandler = new EventHandler
	
	new(IModelManipulations manipulation, G2UTrace traceRoot) {
		this.manipulation = manipulation
		this.traceRoot = traceRoot 
		this.traceEngine = ViatraQueryEngine.on(new EMFScope(traceRoot))
	}
	
	/**
	 * Returns a Set of EObjects that are created of the given "from" object.
	 */
	def getAllValuesOfTo(EObject from) {
		return Traces.Matcher.on(traceEngine).getAllValuesOfto(null, from)
	}
	
	/**
	 * Returns a Set of EObjects that the given "to" object is created of.
	 */
	def getAllValuesOfFrom(EObject to) {
		return Traces.Matcher.on(traceEngine).getAllValuesOffrom(null, to)
	}
	
	def isTraced(EObject object) {
		return !object.allValuesOfTo.empty || 
			!ExpressionTraces.Matcher.on(traceEngine).getAllValuesOfto(null, object).empty
	}
	
	/** 
	 * Returns the ComponentInstance the given object is element of.
	 */
	def ComponentInstance getOwner(EObject object) {
		val traces = InstanceTraces.Matcher.on(traceEngine).getAllValuesOfinstance(null, object)
		if (traces.size != 1) {
			throw new IllegalArgumentException("The number of owners of this object is not one! Object: " + object + " Size: " + traces.size + " Owners: " + traces.map[it.owner])
		}
		return traces.head		
	}
	
	def getPort(VariableDeclaration variable) {
		val traces = PortTraces.Matcher.on(traceEngine).getAllValuesOfport(null, variable)
		if (traces.size != 1) {
			throw new IllegalArgumentException("The number of owners of this object is not one! Object: " + variable + " Size: " + traces.size + " Owners: " + traces.map[it.owner])
		}
		return traces.head		
	}
	
	/** 
	 * Returns the MessageQueueTrace the given queue is saved in.
	 */
	def MessageQueueTrace getTrace(MessageQueue queue, ComponentInstance owner) {
		var traces = MessageQueueTraces.Matcher.on(traceEngine).getAllValuesOftrace(queue)
		if (owner !== null) {
			traces = traces.filter[it.queue.owner === owner].toSet
		}
		if (traces.size != 1) {
			throw new IllegalArgumentException("The number of owners of this object is not one! " + traces)
		}
		return traces.head		
	}
	
	 /** 
	 * Creates a message queue trace.
	 */
	def addQueueTrace(MessageQueue queue, DataVariableDeclaration sizeConst, DataVariableDeclaration capacityVar,
		FunctionDeclaration peekFunction, FunctionDeclaration shiftFunction, FunctionDeclaration pushFunction,
		FunctionDeclaration isFullFunction, DataVariableDeclaration array) {
		traceRoot.createChild(g2UTrace_Traces, messageQueueTrace) as MessageQueueTrace => [
			it.queue = queue
			it.sizeConst = sizeConst
			it.capacityVar = capacityVar
			it.peekFunction = peekFunction
			it.shiftFunction = shiftFunction
			it.pushFunction = pushFunction
			it.isFullFunction = isFullFunction
			it.array = array
		]
	}
	
	/**
	 * Responsible for putting the "from" -> "to" mapping into a trace. If the "from" object is already in
	 * another trace object, it is fetched and it will contain the "to" object as well.
	 */
	def addToTrace(EObject from, Set<EObject> to, EClass traceClass) {
		// So from values will not be duplicated if they are already present in the trace model
		var AbstractTrace aTrace 
		switch (traceClass) {
			case instanceTrace: {
				val instance = from as ComponentInstance
				aTrace = InstanceTraces.Matcher.on(traceEngine).getAllValuesOftrace(instance, null).head
			}
			case portTrace: {
				val port = from as Port
				aTrace = PortTraces.Matcher.on(traceEngine).getAllValuesOftrace(port, null).head
			}
			case expressionTrace: 
				aTrace = ExpressionTraces.Matcher.on(traceEngine).getAllValuesOftrace(from, null).head
			case trace: 
				aTrace = Traces.Matcher.on(traceEngine).getAllValuesOftrace(from, null).head 
		}
		// Otherwise a new trace object is created
		if (aTrace === null) {
			aTrace = traceRoot.createChild(g2UTrace_Traces, traceClass) as AbstractTrace
			switch (traceClass) {
				case instanceTrace: 			
					aTrace.set(instanceTrace_Owner, from)
				case portTrace: 
					aTrace.set(portTrace_Port, from)
				case expressionTrace: 			
					aTrace.addTo(expressionTrace_From, from)
				case trace: 
					aTrace.addTo(trace_From, from)
			}
		}
		val AbstractTrace finalTrace = aTrace
		switch (traceClass) {
				case instanceTrace: 			
					to.forEach[finalTrace.addTo(instanceTrace_Element, it)]
				case portTrace: 
					to.forEach[finalTrace.addTo(portTrace_Declarations, it)]
				case expressionTrace: 			
					to.forEach[finalTrace.addTo(expressionTrace_To, it)]
				case trace: 
					to.forEach[finalTrace.addTo(trace_To, it)]
		}
		return finalTrace
	}
	
	def getAsyncSchedulerChannel(AsynchronousAdapter wrapper) {
		wrapper.allValuesOfTo.filter(ChannelVariableDeclaration).filter[it.variable.head.name.startsWith(wrapper.asyncSchedulerChannelName)].head
	}
	
	def getSyncSchedulerChannel(AsynchronousAdapter wrapper) {
		wrapper.allValuesOfTo.filter(ChannelVariableDeclaration).filter[it.variable.head.name.startsWith(wrapper.syncSchedulerChannelName)].head		
	}
	
	def getInitializedVariable(AsynchronousAdapter wrapper) {
		wrapper.allValuesOfTo.filter(DataVariableDeclaration).filter[it.variable.head.name.startsWith(wrapper.initializedVariableName)].head		
	}
	
	def getAsyncSchedulerChannel(AsynchronousComponentInstance instance) {
		instance.allValuesOfTo.filter(ChannelVariableDeclaration).filter[it.variable.head.name.startsWith(instance.asyncSchedulerChannelName)].head
	}
	
	def getSyncSchedulerChannel(AsynchronousComponentInstance instance) {
		instance.allValuesOfTo.filter(ChannelVariableDeclaration).filter[it.variable.head.name.startsWith(instance.syncSchedulerChannelName)].head		
	}
	
	def getInitializedVariable(AsynchronousComponentInstance instance) {
		instance.allValuesOfTo.filter(DataVariableDeclaration).filter[it.variable.head.name.startsWith(instance.initializedVariableName)].head		
	}
	
	// These dispatch methods are for getting the proper source and target location
	// of a simple edge based on the type of the source/target Gamma state node.
	
	def dispatch List<Location> getEdgeSource(EntryState entry) {
		return entry.getAllValuesOfTo.filter(Location).filter[it.locationTimeKind == LocationKind.COMMITED].toList	
	}
	
	def dispatch List<Location> getEdgeSource(State state) {
		return state.getAllValuesOfTo.filter(Location).filter[it.locationTimeKind == LocationKind.NORMAL].toList
	}
	
	def dispatch List<Location> getEdgeSource(StateNode stateNode) {
		return stateNode.getAllValuesOfTo.filter(Location).toList
	}
	
	def dispatch List<Location> getEdgeTarget(State state) {
		return state.getAllValuesOfTo.filter(Location).filter[it.locationTimeKind == LocationKind.COMMITED].toList
	}
	
	def dispatch List<Location> getEdgeTarget(EntryState entry) {
		return entry.getAllValuesOfTo.filter(Location).filter[it.locationTimeKind == LocationKind.COMMITED].toList
	}
	
	def dispatch List<Location> getEdgeTarget(StateNode stateNode) {
		return stateNode.getAllValuesOfTo.filter(Location).toList
	}
	
	/**
	 * Returns the Uppaal const representing the given signal.
	 */
	def getConstRepresentation(Event event, Port port) {		
		var variables = EventRepresentations.Matcher.on(traceEngine).getAllValuesOfrepresentation(port, event)
		// If the size is 0, it may be because it is a statechart level event and must be transferred to system level: see old code
		if (variables.size != 1) {
			throw new IllegalArgumentException("This event has not one const representations: " + event.name + " Port: " + port.name + " " + variables)
		}
		return variables.head
	}
	
	def getConstRepresentation(Clock clock) {
		val variables = ClockRepresentations.Matcher.on(traceEngine).getAllValuesOfrepresentation(clock)
		if (variables.size > 1) {
			throw new IllegalArgumentException("This clock has more than one const representations: " + clock + " " + variables)
		}
		return variables.head
	}
	
		/**
	 * Returns the Uppaal toRaise boolean flag of a Gamma typed-signal.
	 */
	protected def getToRaiseVariable(Event event, Port port, ComponentInstance instance) {
		var DataVariableDeclaration variable 
		val variables = event.allValuesOfTo.filter(DataVariableDeclaration)
				.filter[it.prefix == DataVariablePrefix.NONE && it.owner == instance]
		if (Collections.singletonList(port).getSemanticEvents(EventDirection.OUT).contains(event)) {
			// This is an out event
			variable = variables.filter[it.variable.head.name.equals(event.getOutEventName(port, instance))].head
		}		
		else {		
			// Else, this is an in event
			if (instance.isCascade) {
				// Cascade components have no toRaise variables, therefore the isRaised is returned
				variable = event.getIsRaisedVariable(port, instance)
			}
			else {
				variable = variables.filter[it.variable.head.name.equals(event.toRaiseName(port, instance))].head
			}	
		}
		if (variable === null) {
			throw new IllegalArgumentException("This event has no toRaiseEvent: " + event.name + " Port: " + port.name + " Instance: " + instance.name)
		}
		return variable
	}	
	
	/**
	 * Returns the Uppaal isRaised boolean flag of a Gamma typed-signal.
	 */
	protected def getIsRaisedVariable(Event event, Port port, ComponentInstance instance) {
		val variable = event.allValuesOfTo.filter(DataVariableDeclaration).filter[it.prefix == DataVariablePrefix.NONE
			&& it.owner == instance && it.variable.head.name.equals(event.isRaisedName(port, instance))].head
		if (variable === null) {
			throw new IllegalArgumentException("This event has no isRaisedEvent: " + event.name + " Port: " + port.name + " Instance: " + instance.name)
		}
		return variable
	}
	
	/**
	 * Returns the Uppaal out-event boolean flag of a Gamma typed-signal.
	 */
	protected def getOutVariable(Event event, Port port, ComponentInstance instance) {
		val variable = event.allValuesOfTo.filter(DataVariableDeclaration).filter[it.prefix == DataVariablePrefix.NONE
			&& it.owner == instance && it.variable.head.name.equals(event.getOutEventName(port, instance))].head
		if (variable === null) {
			throw new IllegalArgumentException("This event has no isRaisedEvent: " + event.name + " Port: " + port.name + " Instance: " + instance.name)
		}
		return variable
	}
	
	// Add to a certain reference
	
	def addToTraceTo(EObject oldRef, EObject newRef) {
		for	(oldTrace : Traces.Matcher.on(traceEngine).getAllValuesOftrace(null, oldRef)) { // Always one trace
			if (oldTrace.from.size > 1) {
				throw new Exception("The OldTrace contains more than one reference.")
			}
			val from = oldTrace.from.head
			addToTrace(from, #{newRef}, trace)		
		}	
	}
	
	def addToExpressionTraceTo(EObject oldRef, EObject newRef) {
		for	(oldTrace : ExpressionTraces.Matcher.on(traceEngine).getAllValuesOftrace(null, oldRef)) { // Always one trace
			if (oldTrace.from.size > 1) {
				throw new Exception("The OldTrace contains more than one reference.")
			}
			val from = oldTrace.from.head
			addToTrace(from, #{newRef}, expressionTrace)		
		}		
	}
	
	// Trace removal
	
	def removeFromTraces(EObject object) {
		val traces = newHashSet
		traces += Traces.Matcher.on(traceEngine).getAllValuesOftrace(null, object)
		for	(oldTrace : traces) { // Always one trace
			val traceRoot = oldTrace.eContainer as G2UTrace
			if (oldTrace.to.size > 1) {
				oldTrace.remove(trace_To, object)
			}
			else {
				traceRoot.traces.remove(oldTrace)
			}		
		}
		val expTraces = new HashSet<ExpressionTrace>(ExpressionTraces.Matcher.on(traceEngine).getAllValuesOftrace(null, object).toSet)
		for	(oldTrace : expTraces) { // Always one trace
			val traceRoot = oldTrace.eContainer as G2UTrace
			if (oldTrace.to.size > 1) {
				oldTrace.remove(expressionTrace_To, object)
			}
			else {
				traceRoot.traces.remove(oldTrace)
			}		
		}
		val instanceTraces = new HashSet<InstanceTrace>(InstanceTraces.Matcher.on(traceEngine).getAllValuesOftrace(null, object).toSet)
		for	(oldTrace : instanceTraces) { // Always one trace
			val traceRoot = oldTrace.eContainer as G2UTrace
			if (oldTrace.element.size > 1) {
				oldTrace.remove(instanceTrace_Element, object)
			}
			else {
				traceRoot.traces.remove(oldTrace)
			}		
		}
	}	
	
	def dispatch void removeTrace(EObject object) {
		throw new IllegalArgumentException("This object cannot be removed from trace: " + object)
	}
	
	def dispatch void removeTrace(Edge edge) {
		if (edge.synchronization !== null) {
			edge.synchronization.removeTrace		
		}
		if (edge.guard !== null) {
			edge.guard.removeTrace		
		}
		edge.update.forEach[it.removeTrace]
		edge.removeFromTraces
	}
	
	def dispatch void removeTrace(Location object) {
		if (object.invariant !== null) {
			object.invariant.removeTrace
		}
		object.removeFromTraces
	}
	
	def dispatch void removeTrace(Synchronization object) {
		object.channelExpression.removeTrace
		object.removeFromTraces
	}
	
	def dispatch void removeTrace(BinaryExpression object) {
		object.firstExpr.removeTrace
		object.secondExpr.removeTrace
		object.removeFromTraces
	}
	
	def dispatch void removeTrace(IdentifierExpression object) {
		object.removeFromTraces
	}
	
	def dispatch void removeTrace(NegationExpression object) {
		object.negatedExpression.removeTrace
		object.removeFromTraces
	}
	
	def dispatch void removeTrace(PlusExpression object) {
		object.confirmedExpression.removeTrace
		object.removeFromTraces
	}
	
	def dispatch void removeTrace(MinusExpression object) {
		object.invertedExpression.removeTrace
		object.removeFromTraces
	}
	
	def dispatch void removeTrace(LiteralExpression object) {
		object.removeFromTraces
	}
	
}