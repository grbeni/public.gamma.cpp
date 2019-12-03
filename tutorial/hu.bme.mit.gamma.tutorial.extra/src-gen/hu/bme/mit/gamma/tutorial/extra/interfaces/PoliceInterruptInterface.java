package hu.bme.mit.gamma.tutorial.extra.interfaces;

import java.util.List;

public interface PoliceInterruptInterface {
	
	interface Provided extends Listener.Required {
		
		public boolean isRaisedPolice();
		
		void registerListener(Listener.Provided listener);
		List<Listener.Provided> getRegisteredListeners();
	}
	
	interface Required extends Listener.Provided {
		
		
		void registerListener(Listener.Required listener);
		List<Listener.Required> getRegisteredListeners();
	}
	
	interface Listener {
		
		interface Provided  {
			void raisePolice();
		}
		
		interface Required  {
		}
		
	}
}
