package hu.bme.mit.gamma.tutorial.extra.interfaces;

import java.util.List;

public interface MonitorInterface {
	
	interface Provided extends Listener.Required {
		
		public boolean isRaisedError();
		
		void registerListener(Listener.Provided listener);
		List<Listener.Provided> getRegisteredListeners();
	}
	
	interface Required extends Listener.Provided {
		
		
		void registerListener(Listener.Required listener);
		List<Listener.Required> getRegisteredListeners();
	}
	
	interface Listener {
		
		interface Provided  {
			void raiseError();
		}
		
		interface Required  {
		}
		
	}
}
