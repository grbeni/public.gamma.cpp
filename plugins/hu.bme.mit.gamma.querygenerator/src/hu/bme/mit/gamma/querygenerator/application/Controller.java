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
package hu.bme.mit.gamma.querygenerator.application;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintWriter;
import java.util.AbstractMap;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Map.Entry;
import java.util.Scanner;
import java.util.concurrent.CancellationException;
import java.util.concurrent.ExecutionException;
import java.util.logging.Level;
import java.util.logging.Logger;

import javax.swing.JComboBox;
import javax.swing.SwingWorker;

import org.eclipse.core.resources.IFile;
import org.eclipse.core.resources.IncrementalProjectBuilder;
import org.eclipse.core.runtime.CoreException;
import org.eclipse.emf.common.util.URI;
import org.eclipse.emf.ecore.EObject;
import org.eclipse.emf.ecore.resource.ResourceSet;
import org.eclipse.emf.ecore.resource.impl.ResourceSetImpl;
import org.eclipse.viatra.query.runtime.api.ViatraQueryEngine;
import org.eclipse.viatra.query.runtime.emf.EMFScope;
import org.eclipse.viatra.query.runtime.exception.ViatraQueryException;

import com.google.inject.Injector;

import hu.bme.mit.gamma.dialog.DialogUtil;
import hu.bme.mit.gamma.querygenerator.patterns.InstanceStates;
import hu.bme.mit.gamma.querygenerator.patterns.InstanceVariables;
import hu.bme.mit.gamma.querygenerator.patterns.SimpleInstances;
import hu.bme.mit.gamma.querygenerator.patterns.SimpleStatechartStates;
import hu.bme.mit.gamma.querygenerator.patterns.SimpleStatechartVariables;
import hu.bme.mit.gamma.querygenerator.patterns.StatesToLocations;
import hu.bme.mit.gamma.querygenerator.patterns.Subregions;
import hu.bme.mit.gamma.statechart.model.Region;
import hu.bme.mit.gamma.statechart.model.State;
import hu.bme.mit.gamma.trace.language.ui.internal.LanguageActivator;
import hu.bme.mit.gamma.trace.language.ui.serializer.TraceLanguageSerializer;
import hu.bme.mit.gamma.trace.model.ExecutionTrace;
import hu.bme.mit.gamma.uppaal.backannotation.EmptyTraceException;
import hu.bme.mit.gamma.uppaal.backannotation.StringTraceBackAnnotator;
import hu.bme.mit.gamma.uppaal.backannotation.TestGenerator;

public class Controller {

	protected Logger logger = Logger.getLogger("GammaLogger");
	
	private View view;
	
	private ResourceSet resourceSet;
	private ViatraQueryEngine engine;
	private ResourceSet traceabilitySet;
	private ViatraQueryEngine traceEngine;
	// Indicates the actual verification process
	private volatile Verifier verifier;
	// Indicates the actual test generation process
	private volatile GeneratedTestVerifier generatedTestVerifier;
	// Indicates whether back-annotation during verification is needed
	private final boolean needsBackAnnotation;
	
	// The location of the model on which this query generator is opened
	// E.g.: F:/eclipse_ws/sc_analysis_comp_oxy/runtime-New_configuration/hu.bme.mit.inf.gamma.tests/model/TestOneComponent.gsm
	private IFile file;

	private final String TEST_GEN_FOLDER_NAME = "test-gen";
	private final String TRACE_FOLDER_NAME = "trace";
	
	public Controller(View view, ResourceSet resourceSet, IFile file, boolean needsBackAnnotation) throws ViatraQueryException {
		this.file = file;
		this.view = view;
		this.resourceSet = resourceSet;
		logger.log(Level.INFO, "Resource set content for displaying model elements on GUI: " + resourceSet);
		this.traceabilitySet = loadTraceability(); // For state-location
		logger.log(Level.INFO, "Traceability resource set content: " + traceabilitySet);
		this.engine = ViatraQueryEngine.on(new EMFScope(this.resourceSet));
		this.traceEngine = ViatraQueryEngine.on(new EMFScope(this.traceabilitySet));
		this.needsBackAnnotation = needsBackAnnotation;
	}
	
	public void initSelectorWithStates(JComboBox<String> selector) throws ViatraQueryException {
		// Needed to ensure the items in the selector are sorted
		List<String> entryList = new ArrayList<String>();
		// In case of composite systems
		if (isCompositeSystem()) {
			for (InstanceStates.Match statesMatch : InstanceStates.Matcher.on(engine).getAllMatches()) {
				String entry = statesMatch.getInstanceName() + "." + getFullRegionPathName(statesMatch.getParentRegion()) + "." + statesMatch.getStateName();
				if (!statesMatch.getState().getName().startsWith("LocalReaction")) {
					entryList.add(entry);				
				}
			}
		}
		else {
			// In case of single statecharts
			for (SimpleStatechartStates.Match statesMatch : SimpleStatechartStates.Matcher.on(engine).getAllMatches()) {
				String entry = statesMatch.getRegion().getName() + "." + statesMatch.getStateName();
				if (!statesMatch.getState().getName().startsWith("LocalReaction")) {
					entryList.add(entry);				
				}
			}
		}
		fillComboBox(selector, entryList);
	}
	
	public void initSelectorWithVariables(JComboBox<String> selector) throws ViatraQueryException {
		// Needed to ensure the items in the selector are sorted
		List<String> entryList = new ArrayList<String>();
		// In case of composite systems
		if (isCompositeSystem()) {
			for (InstanceVariables.Match statesMatch : InstanceVariables.Matcher.on(engine).getAllMatches()) {
				String entry = statesMatch.getInstance().getName() + "." + statesMatch.getVariable().getName();
				entryList.add(entry);
			}
		}
		else {
			// In case of single statecharts
			for (SimpleStatechartVariables.Match statesMatch : SimpleStatechartVariables.Matcher.on(engine).getAllMatches()) {
				String entry = statesMatch.getVariable().getName();
				entryList.add(entry);
			}	
		}
		fillComboBox(selector, entryList);
	}
	
	public List<String> getStateNames() throws ViatraQueryException {
		List<String> stateNames = new ArrayList<String>();
		// In case of composite systems
		if (isCompositeSystem()) {
			for (InstanceStates.Match statesMatch : InstanceStates.Matcher.on(engine).getAllMatches()) {
				String entry = statesMatch.getInstanceName() + "." + getFullRegionPathName(statesMatch.getParentRegion()) + "." + statesMatch.getStateName();
				if (!statesMatch.getState().getName().startsWith("LocalReaction")) {
					stateNames.add(entry);				
				}
			}
		}
		else {
			// In case of single statecharts
			for (SimpleStatechartStates.Match statesMatch : SimpleStatechartStates.Matcher.on(engine).getAllMatches()) {
				String entry = statesMatch.getRegionName() + "." + statesMatch.getStateName();
				if (!statesMatch.getState().getName().startsWith("LocalReaction")) {
					stateNames.add(entry);				
				}
			}
		}
		return stateNames;
	}
	
	public List<String> getVariableNames() throws ViatraQueryException {
		List<String> variableNames = new ArrayList<String>();
		if (isCompositeSystem()) {
			// In case of composite systems
			for (InstanceVariables.Match variableMatch : InstanceVariables.Matcher.on(engine).getAllMatches()) {
				String entry = variableMatch.getInstance().getName() + "." + variableMatch.getVariable().getName();
				variableNames.add(entry);
			}
		}
		else {
			// In case of single statecharts
			for (SimpleStatechartVariables.Match variableMatch : SimpleStatechartVariables.Matcher.on(engine).getAllMatches()) {
				String entry = variableMatch.getVariable().getName();
				variableNames.add(entry);
			}
		}
		return variableNames;
	}
	
	/** Returns the chain of regions from the given lowest region to the top region. 
	 */
	private String getFullRegionPathName(Region lowestRegion) {
		if (!(lowestRegion.eContainer() instanceof State)) {
			return lowestRegion.getName();
		}
		String fullParentRegionPathName = getFullRegionPathName((Region) lowestRegion.eContainer().eContainer());
		return fullParentRegionPathName + "." + lowestRegion.getName(); // Only regions are in path - states could be added too
	}
	
	public String parseRegular(String text, String operator) throws ViatraQueryException {
		String result = text;
		List<String> stateNames = this.getStateNames();
		List<String> variableNames = this.getVariableNames();
		for (String stateName : stateNames) {
			if (result.contains("(" + stateName + ")")) {
				String uppaalStateName = getUppaalStateName(stateName);
				// The parentheses need to be \-d
				result = result.replaceAll("\\(" + stateName + "\\)", "\\(" + uppaalStateName + "\\)");
			}
			// Checking the negations
			if (result.contains("(!" + stateName + ")")) {
				String uppaalStateName = getUppaalStateName(stateName);
				// The parentheses need to be \-d
				result = result.replaceAll("\\(!" + stateName + "\\)", "\\(!" + uppaalStateName + "\\)");
			}
		}
		for (String variableName : variableNames) {
			if (result.contains("(" + variableName + ")")) {
				String uppaalVariableName = getUppaalVariableName(variableName);
				result = result.replaceAll("\\(" + variableName + "\\)", "\\(" + uppaalVariableName + "\\)");
			}
			// Checking the negations
			if (result.contains("(!" + variableName + ")")) {
				String uppaalVariableName = getUppaalVariableName(variableName);
				result = result.replaceAll("\\(!" + variableName + "\\)", "\\(!" + uppaalVariableName + "\\)");
			}
		}
		result = "(" + result + ")";
		if (isCompositeSystem() && !operator.equals(View.MIGHT_ALWAYS) && !operator.equals(View.MUST_ALWAYS)) {
			// It is pointless to add isStable in cases of A[] and E[]
			result += " && isStable";
		}
		else if (isCompositeSystem()){
			// Instead this is added
			result += " || !isStable";
		}
		return result;
	}
	
	private String getUppaalStateName(String stateName) throws ViatraQueryException {
		logger.log(Level.INFO, stateName);
		String[] splittedStateName = stateName.split("\\.");
		if (isCompositeSystem()) {
			// In case of composite systems
			for (InstanceStates.Match match : InstanceStates.Matcher.on(engine).getAllMatches(null, splittedStateName[0],
					null, splittedStateName[splittedStateName.length - 2] /* parent region */,
					null, splittedStateName[splittedStateName.length - 1] /* state */)) {
				Region parentRegion = match.getParentRegion();
				String templateName = "P_" + getRegionName(parentRegion) + "Of" + splittedStateName[0] /* instance name */;
				StringBuilder locationNames = new StringBuilder("(");
				for (String locationName : StatesToLocations.Matcher.on(traceEngine).getAllValuesOflocationName(match.getState().getName())) {
					String templateLocationName = templateName +  "." + locationName;
					if (locationNames.length() == 1) {
						// First append
						locationNames.append(templateLocationName);
					}
					else {
						locationNames.append(" || " + templateLocationName);
					}
				}
				locationNames.append(")");
				if (isSubregion(parentRegion)) {
					locationNames.append(" && " + templateName + ".isActive"); 
				}
				return locationNames.toString();
			}
		}
		else {
			// In case of single statecharts
			for (SimpleStatechartStates.Match match : SimpleStatechartStates.Matcher.on(engine).getAllMatches(null, splittedStateName[0], null, splittedStateName[1])) {
				Region parentRegion = (Region) match.getState().eContainer();
				return "P_" + getRegionName(parentRegion) + "." + splittedStateName[1];
			}
		}
		throw new IllegalArgumentException("No!");
	}
	
	private String getUppaalVariableName(String variableName) throws ViatraQueryException {		
		if (isCompositeSystem()) {
			// In case of composite systems
			String[] splittedStateName = variableName.split("\\.");
			return splittedStateName[1] + "Of" + splittedStateName[0];
		}
		// In case of single statecharts
		return variableName;
	}
	
	/**
	 * Returns whether the model on which the queries are generated is a composite system.
	 */
	private boolean isCompositeSystem() throws ViatraQueryException {
		return (SimpleInstances.Matcher.on(engine).countMatches() > 0);
	}
	
	private boolean isSubregion(Region region) throws ViatraQueryException {
		return Subregions.Matcher.on(engine).countMatches(region, null) > 0;
	}
	
	/**
     * Returns the template name of a region.
     */
    private String getRegionName(Region region) throws ViatraQueryException {
    	String templateName;
    	if (isSubregion(region)) {
			templateName = (region.getName() + "Of" + ((State) region.eContainer()).getName());
		}
		else {			
			templateName = (region.getName()  + "OfStatechart");
		}
		return templateName.replaceAll(" ", "");
	}
    
    private void fillComboBox(JComboBox<String> selector, List<String> entryList) {
    	Collections.sort(entryList);
    	for (String item : entryList) {
    		selector.addItem(item);
    	}
    }

    /**
     * Returns the next valid name for the file containing the back-annotation.
     */
    private Map.Entry<String, Integer> getFileName(String fileExtension) throws CoreException {
    	final String TRACE_FILE_NAME = "ExecutionTrace";
    	List<Integer> usedIds = new ArrayList<Integer>();
    	File traceFile = new File(getTraceFolder());
    	traceFile.mkdirs();
    	// Searching the trace folder for highest id
    	for (File file: new File(getTraceFolder()).listFiles()) {
    		if (file.getName().matches(TRACE_FILE_NAME + "[0-9]+\\..*")) {
    			String id = file.getName().substring(TRACE_FILE_NAME.length(), file.getName().length() - ("." + fileExtension).length());
    			usedIds.add(Integer.parseInt(id));
    		}
    	}
    	if (usedIds.isEmpty()) {
    		return new AbstractMap.SimpleEntry<String, Integer>(
    				TRACE_FILE_NAME + "0." + fileExtension, 0);
    	}
    	Collections.sort(usedIds);
    	Integer biggestId = usedIds.get(usedIds.size() - 1);
    	return new AbstractMap.SimpleEntry<String, Integer>(
    			TRACE_FILE_NAME + (biggestId + 1) + "." + fileExtension, (biggestId + 1));
    }
    
    private String getTestGentFolder() {
		return file.getProject().getLocation() + File.separator + TEST_GEN_FOLDER_NAME;
	}
    
    private String getTraceFolder() {
		return URI.decode(file.getProject().getLocation() + File.separator + TRACE_FOLDER_NAME);
	}
    
	private String getParentFolder() {
		return getLocation(file).substring(0, getLocation(file).lastIndexOf("/"));
	}
	
	private String getCompositeSystemName() {
		return getLocation(file).substring(getLocation(file).lastIndexOf("/") + 1, getLocation(file).lastIndexOf("."));
	}
	
	private String getTraceabilityFile() {
		return getParentFolder() + File.separator + "." + getCompositeSystemName() + ".g2u"; 
	}
	
	private String getGeneratedQueryFile() {
		return getParentFolder() + File.separator + getCompositeSystemName() + ".q"; 
	}
	
	private String getUppaalXmlFile() {
		return getLocation(file).substring(0, getLocation(file).lastIndexOf(".")) + ".xml";
	}
	
	@SuppressWarnings("unused")
	private boolean isWindows() {
		return System.getProperty("os.name").toLowerCase().indexOf("win") >= 0;
	}
	
	private String getLocation(IFile file) {
		return URI.decode(file.getLocation().toString());
	}
	
	private void serialize(EObject rootElem, String parentFolder, String fileName) throws IOException {
		// This is how an injected object can be retrieved
		Injector injector = LanguageActivator.getInstance()
				.getInjector(LanguageActivator.HU_BME_MIT_GAMMA_TRACE_LANGUAGE_TRACELANGUAGE);
		TraceLanguageSerializer serializer = injector.getInstance(TraceLanguageSerializer.class);
		serializer.save(rootElem, URI.decode(parentFolder + File.separator + fileName));
   }
	
	private File writeToFile(String string, String parentFolder, String fileName) throws FileNotFoundException {
		new File(parentFolder).mkdirs(); // Creating parent folder if needed
		String fileLocation = parentFolder + File.separator + fileName;
		File file = new File(fileLocation);
		try (PrintWriter writer = new PrintWriter(fileLocation)) {
			writer.print(string);
		}
		return file;
	}
	
	private ResourceSet loadTraceability() {
		ResourceSet resSet = new ResourceSetImpl();
		logger.log(Level.INFO, "Resource set created for traceability: " + resSet);
		URI fileURI = URI.createFileURI(getTraceabilityFile());
		try {
			resSet.getResource(fileURI, true);
		} catch (RuntimeException e) {
			e.printStackTrace();
			return null;
		}
		return resSet;
	}
	/**
	 * Cancels the actual verification process. Returns true if a process has been cancelled.
	 */
	public boolean cancelVerification() {
		if (verifier != null) {
			verifier.cancelProcess(true);
			return true;
		}
		if (generatedTestVerifier != null) {
			generatedTestVerifier.cancelProcess();
			return true;
		}
		return false;
	}
	
	/**
	 * Verifies the given Uppaal query.
	 */
	public void verify(String uppaalQuery) {
		verifier = new Verifier(uppaalQuery, true);
		// Starting the worker
		verifier.execute();
	}
    
    /**
     * Verifies the generated Uppaal queries.
     */
    public void executeGeneratedQueries() {
    	generatedTestVerifier = new GeneratedTestVerifier();
		Thread thread = new Thread(generatedTestVerifier);
    	thread.start();
    }
	
	private String getParameters() {
		return getSearchOrder() + " " + getDiagnosticTrace() + " " + getHashtableSize() + " " +
				getStateSpaceReduction();
	}
	
	private String getSearchOrder() {
		final String paremterName = "-o ";
		switch (view.getSelectedSearchOrder()) {
		case "Breadth First":
			// BFS
			return paremterName + "0";
		case "Depth First":
			// DFS
			return paremterName + "1";
		case "Random Depth First":
			// Random DFS
			return paremterName + "2";			
		default:
			throw new IllegalArgumentException("Not known option: " + view.getSelectedSearchOrder());
		}
	}
	
	private String getHashtableSize() {
		/* -H n
	      Set hash table size for bit state hashing to 2**n
	      (default = 27)
		 */
		final String paremterName = "-H ";
		final int value = view.getHashTableSize();
		final int exponent = 20 + (int) Math.floor(Math.log10(value) / Math.log10(2)); // log2(value)
		return paremterName + exponent;
	}
	
	private String getStateSpaceReduction() {
		final String paremterName = "-S ";
		switch (view.getStateSpaceReduction()) {
		case "None":
			// BFS
			return paremterName + "0";
		case "Conservative":
			// DFS
			return paremterName + "1";
		case "Aggressive":
			// Random DFS
			return paremterName + "2";			
		default:
			throw new IllegalArgumentException("Not known option: " + view.getStateSpaceReduction());
		}
	}
	
	private String getDiagnosticTrace() {
		switch (view.getSelectedTrace()) {
		case "Some":
			// Some trace
			return "-t0";
		case "Shortest":
			// Shortest trace
			return "-t1";
		case "Fastest":
			// Fastest trace
			return "-t2";			
		default:
			throw new IllegalArgumentException("Not known option: " + view.getSelectedTrace());
		}
	}
	
	/** Runnable class responsible for the execution of formal verification. */
	class Verifier extends SwingWorker<ThreeStateBoolean, Boolean> {
		// The query needs to be added to UPPAAL in addition to the model
		private String uppaalQuery;		
		// Process running the UPPAAL verification
		private Process process;
		// Indicates whether this worker is cancelled: needed as the original isCancelled is updated late
		private volatile boolean isCancelled = false;
		// Indicates whether it should contribute to the View in any form
		private boolean contributeToView;
		
		public Verifier(String uppaalQuery, boolean contributeToView) {
			this.uppaalQuery = uppaalQuery;
			this.contributeToView = contributeToView;
		}
		
		@Override
		public ThreeStateBoolean doInBackground() throws Exception {
			Scanner traceReader = null;
			try {
				// Disabling the verification buttons
				view.setVerificationButtons(false);
				// Writing the query to a temporary file
				File tempQueryfile = writeToFile(uppaalQuery, getParentFolder(), ".temporary_query.q");
				// Deleting the file on the exit of the JVM
				tempQueryfile.deleteOnExit();
				// verifyta -t1 TestOneComponent.xml asd.q 
				StringBuilder command = new StringBuilder();
				command.append("verifyta " + getParameters() + " \"" + getUppaalXmlFile() + "\" \"" + tempQueryfile.getCanonicalPath() + "\"");
				// Executing the command
				process = Runtime.getRuntime().exec(command.toString());
				InputStream ips = process.getErrorStream();
				// Reading the result of the command
				traceReader = new Scanner(ips);
				if (isCancelled) {
					// If the process is killed, this is where it can be checked
					return ThreeStateBoolean.UNDEF;
				}
				if (!traceReader.hasNext()) {
					// No back annotation of empty lines
					return handleEmptyLines(uppaalQuery);
				}
				// Warning lines are now deleted if there was any
				ResourceSet traceabilitySet = loadTraceability(); // For back-annotation
				logger.log(Level.INFO, "Resource set content for string trace back-annotation: " + traceabilitySet);
				StringTraceBackAnnotator backAnnotator = new StringTraceBackAnnotator(traceabilitySet, traceReader);
				ExecutionTrace traceModel = backAnnotator.execute();
				if (!needsBackAnnotation) {
					// If back-annotation is not needed, we return after checking if it is an empty trace (watching out for warning lines)
					return handleEmptyLines(uppaalQuery).opposite();
				}
				Entry<String, Integer> fileNameAndId = getFileName("get"); // File extension could be gtr or get		
				fileNameAndId = saveModel(traceModel, fileNameAndId);
				// Have to be the SAME resource set as before (traceabilitySet) otherwise the trace model contains references to dead objects
				String packageName = file.getProject().getName().toLowerCase();
				TestGenerator testGenerator = new TestGenerator(traceabilitySet,
					traceModel, packageName, "ExecutionTraceSimulation" + fileNameAndId.getValue());
				String testClassCode = testGenerator.execute();
				String testClassParentFolder = getTestGentFolder() + "/" + 
						testGenerator.getPackageName().replaceAll("\\.", "\\/");
				writeToFile(testClassCode, testClassParentFolder,
						"ExecutionTraceSimulation" + fileNameAndId.getValue() + ".java");
				logger.log(Level.INFO, "Test generation has been finished.");
				// There is a generated trace, so the result is the opposite of the empty trace
				return handleEmptyLines(uppaalQuery).opposite();
			} catch (EmptyTraceException e) {
				return handleEmptyLines(uppaalQuery);
			} catch (NullPointerException e) {
				e.printStackTrace();
				throw new IllegalArgumentException("Error! The generated UPPAAL file cannot be found.");
			} catch (FileNotFoundException e) {
				throw new IllegalArgumentException("Error! The generated UPPAAL file cannot be found.");
			} catch (Throwable e) {
				IllegalArgumentException ex = new IllegalArgumentException("Error! " + e.getMessage());
				ex.initCause(e);
				throw ex;
			} finally {
				traceReader.close();
			}
		}

		private Entry<String, Integer> saveModel(ExecutionTrace traceModel, Entry<String, Integer> fileNameAndId)
				throws CoreException, IOException {
			try {
				// Trying to serialize the model
				serialize(traceModel, getTraceFolder(), fileNameAndId.getKey());
			} catch (Exception e) {
				logger.log(Level.SEVERE, e.getMessage() + System.lineSeparator() +
					"Possibly you have two more model elements with the same name specified in the previous error message.");
				new File(getTraceFolder() + File.separator + fileNameAndId.getKey()).delete();
				// Saving like an EMF model
				fileNameAndId = getFileName("gtr");
				serialize(traceModel, getTraceFolder(), fileNameAndId.getKey());
			}
			return fileNameAndId;
		}
		
		/**
		 * Returns the correct verification answer when there is no generated trace by the UPPAAL.
		 */
		private ThreeStateBoolean handleEmptyLines(String uppaalQuery) {
			if (uppaalQuery.startsWith("A[]") || uppaalQuery.startsWith("A<>")) {
				// In case of A, empty trace means the requirement is met
				return ThreeStateBoolean.TRUE;
			}
			// In case of E, empty trace means the requirement is not met
			return ThreeStateBoolean.FALSE;
		}
		
		@Override
		protected void process(final List<Boolean> chunks) {}
		
		/**
		 * Releases the verifyta process.
		 */
		private void destroyProcess() {
			// Killing the process
			if (process != null) {
				process.destroy();
				try {
					// Waiting for process to end
					process.waitFor();
				} catch (InterruptedException e) {}
			}
		}
		
		/**
		 * Cancels this particular Verifier object.
		 */
		public boolean cancelProcess(boolean mayInterrupt) {
			isCancelled = true;
			destroyProcess();
			return super.cancel(mayInterrupt);
		}
		
		public boolean isProcessCancelled() {
			return isCancelled;
		}
		 
		@Override
		protected void done() {
			try {
				if (contributeToView) {
					ThreeStateBoolean result = get();
					if (!isCancelled) {
						if (result == ThreeStateBoolean.TRUE) {
							view.setVerificationLabelToTrue();
						}
						else if (result == ThreeStateBoolean.FALSE) {
							view.setVerificationLabelToFalse();
						}
					}
				}
			} catch (ExecutionException e) {
				e.printStackTrace();
				view.handleVerificationExceptions((Exception) e.getCause());
			} catch (InterruptedException | CancellationException e) {
				// Killing the process
				destroyProcess();
			} finally {
				// Removing this object from the attributes
				if (verifier == this) {
					verifier = null;
				}
				if (generatedTestVerifier == null) {
					// Enabling the verification buttons only if it is a simple query
					view.setVerificationButtons(true);
				}
			}
		}
		
	}

    class GeneratedTestVerifier implements Runnable {
    	// Indicates whether the test generation process is cancelled
    	private volatile boolean isCancelled = false;
    	
	    /**
	     * Verifies all generated Uppaal queries (deadlock and reachability).
	     */
    	@Override
	    public void run() {
	    	final int TIMEOUT = 40;
	    	final int SLEEP_INTERVAL = 250;
	    	Verifier verifier = null;
	    	StringBuilder buffer = new StringBuilder();
	    	// Disabling the verification buttons
			view.setVerificationButtons(false);
	    	try (BufferedReader reader = new BufferedReader(new FileReader(new File(getGeneratedQueryFile())))) {
	    		String uppaalQuery;
	    		while ((uppaalQuery = reader.readLine()) != null && !isCancelled) {
	    			Logger.getLogger("GammaLogger").log(Level.INFO, "Checking " + uppaalQuery + "...");
	    			verifier = new Verifier(uppaalQuery, false);
	    			verifier.execute();
    				int elapsedTime = 0;
    				while (!verifier.isDone() && elapsedTime < TIMEOUT && !isCancelled) {
    					Thread.sleep(SLEEP_INTERVAL);    			
    					++elapsedTime;
    				}
    				if (verifier.isDone() && !verifier.isProcessCancelled() /*needed as cancellation does not interrupt this method*/) {
    					String stateName = "";
						if (!uppaalQuery.equals("A[] not deadlock")) {
							if (uppaalQuery.startsWith("E<> ")) {
								stateName =  uppaalQuery.substring("E<> ".length());
							}
						}
						if (stateName.endsWith( " && isStable")) {
							stateName = stateName.substring(0, stateName.length() - " && isStable".length());
						}
    					if (stateName.startsWith("P_")) {
    						stateName = stateName.substring("P_".length());
    					}
    					String resultSentence = null;
    					ThreeStateBoolean result = verifier.get();
    					if (uppaalQuery.equals("A[] not deadlock")) {
    						// Deadlock query
    						switch (result) {
    							case TRUE:
    								resultSentence = "No deadlock.";
    							break;
    							case FALSE:
    								resultSentence = "There can be deadlock in the system.";
    							break;
    							case UNDEF:
    								// Theoretically unreachable because of !cancelled
    								resultSentence = "Not determined if there can be deadlock.";
    							break;
    						}
    					}
    					else {
    						// Reachability query
    						String isReachableString  = null;
    						switch (result) {
								case TRUE:
									isReachableString = "reachable";
								break;
								case FALSE:
									isReachableString = "unreachable";
								break;
								case UNDEF:
    								// Theoretically unreachable because of !cancelled
									isReachableString = "undefined";
								break;
    						}
    						resultSentence = stateName + " is " + isReachableString + ".";
    					}
						buffer.append(resultSentence + System.lineSeparator());
						Logger.getLogger("GammaLogger").log(Level.INFO, resultSentence); // Removing temporal operator
    				}
    				else if (elapsedTime >= TIMEOUT) {
    					Logger.getLogger("GammaLogger").log(Level.INFO, "Timeout...");
    				}
    				// Important to cancel the process
    				verifier.cancelProcess(true);
	    		}
			} catch (Exception e) {
				view.handleVerificationExceptions(e);
			} finally {
				if (generatedTestVerifier == this) {
					// Removing this object from the attributes
					generatedTestVerifier = null;
				}
				if (verifier != null && !verifier.isProcessCancelled()) {
					verifier.cancelProcess(true);
				}
				// Enabling the verification buttons
				view.setVerificationButtons(true);
			}
	    	if (!isCancelled) {
	    		// Writing this only if the process has not been cancelled
	    		view.setVerificationLabel("Finished generation.");
	    	}
	    	if (buffer.length() > 0) {
	    		DialogUtil.showInfo(buffer.toString());
	    	}
	    	try {
	    		logger.log(Level.INFO, "Cleaning project...");
				file.getProject().build(IncrementalProjectBuilder.CLEAN_BUILD, null);
				logger.log(Level.INFO, "Cleaning project finished.");
			} catch (CoreException e) {
				// Nothing we can do
			}
	    }
    	
    	public void cancelProcess() {
    		isCancelled = true;
    	}
    	
    }
    
}

enum ThreeStateBoolean {
	FALSE, TRUE, UNDEF;
	
	public ThreeStateBoolean opposite() {
		switch (this) {
			case FALSE:
				return TRUE;
			case TRUE:
				return FALSE;
			default:
				return UNDEF;
		}		
	}
	
}
