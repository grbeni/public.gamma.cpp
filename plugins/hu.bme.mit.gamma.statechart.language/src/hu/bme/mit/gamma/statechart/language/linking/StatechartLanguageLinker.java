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
package hu.bme.mit.gamma.statechart.language.linking;

import java.util.Collections;
import java.util.List;

import org.eclipse.emf.common.util.URI;
import org.eclipse.emf.ecore.EObject;
import org.eclipse.emf.ecore.EReference;
import org.eclipse.emf.ecore.resource.Resource;
import org.eclipse.emf.ecore.resource.ResourceSet;
import org.eclipse.emf.ecore.resource.impl.ResourceSetImpl;
import org.eclipse.xtext.conversion.IValueConverterService;
import org.eclipse.xtext.linking.impl.DefaultLinkingService;
import org.eclipse.xtext.nodemodel.INode;

import com.google.inject.Inject;

import hu.bme.mit.gamma.statechart.model.Package;
import hu.bme.mit.gamma.statechart.model.StatechartModelPackage;

public class StatechartLanguageLinker extends DefaultLinkingService {

    @Inject IValueConverterService valueConverterService;
    
    public static StatechartModelPackage pack = StatechartModelPackage.eINSTANCE;
    
    public List<EObject> getLinkedObjects(EObject context, EReference ref, INode node) {
    	if (context instanceof Package) {
    		if (ref == pack.getPackage_Imports()) {
    			try {
		    		Package root = (Package) context;
		    		String path = valueConverterService.toValue(node.getText(),
		    				getLinkingHelper().getRuleNameFrom(node.getGrammarElement()), node).toString().replaceAll("\\s","");
		    		Resource rootResource = root.eResource();
		    		ResourceSet resourceSet = rootResource.getResourceSet();
		    		// Adding the gcd extension, if needed
		    		String finalPath = addExtensionIfNeeded(path);
		    		if (!isCorrectPath(finalPath)) {
		    			// Path of the importer model
		    			String rootResourceUri = rootResource.getURI().toString();
		    			StringBuilder pathBuilder = new StringBuilder(finalPath);
		    			// If the path starts with a '/', we delete it
		    			if (pathBuilder.charAt(0) == '/') {
		    				pathBuilder.deleteCharAt(0);
		    			}
		    			String[] splittedRootResourceUri = rootResourceUri.split("/");
		    			int originalCharacterIndex = 0;
		    			for (int i = 0; i < splittedRootResourceUri.length && !isCorrectPath(pathBuilder.toString()); ++i) {
		    				// Trying prepending the folders one by one
		    				String prepension = splittedRootResourceUri[i] + "/";
		    				pathBuilder.insert(originalCharacterIndex, prepension);
		    				originalCharacterIndex += prepension.length();
		    			}
		    			// Finished
		    			finalPath = pathBuilder.toString();
		    		}
		    		URI uri = URI.createURI(finalPath);
		    		Resource importedResource = resourceSet.getResource(uri, true);
		    		EObject importedPackage = importedResource.getContents().get(0);
		    		return Collections.singletonList(importedPackage);
    			} catch (Exception e) {
    				// Trivial case: most of the time (during typing) the uri is not correct, thus the loading cannot be done
    			}
    		}	
    	}
    	return super.getLinkedObjects(context, ref, node);
    }
    
    private boolean isCorrectPath(String path) {
    	if (!path.startsWith("platform:/resource/")) {
    		return false;
    	}
    	ResourceSet resourceSet = new ResourceSetImpl();
		URI uri = URI.createURI(path);
		try {
	    	resourceSet.getResource(uri, true);
	    	resourceSet.getResources().get(0).unload();
	    	resourceSet.getResources().clear();
	    	resourceSet = null;
	    	return true;
		} catch (Exception e) {
			// Resource cannot be loaded due to invalid path
			return false;
		}
    }
    
    private String addExtensionIfNeeded(String path) {
    	String[] splittedPath = path.split("/");
    	String fileName = splittedPath[splittedPath.length - 1];
    	String[] splittedFileName = fileName.split("\\.");
    	if (splittedFileName.length == 1) {
    		return path + ".gcd";
    	}
    	return path;
    }
	
}