terraform {                                                                                                                                                                                             
    required_version = ">= 1.5.0"                                                                                                                                                                         
                                                                                                                                                                                                          
    required_providers {                                                                                                                                                                                  
      kind = {                                                                                                                                                                                            
        source  = "tehcyx/kind"                                                                                                                                                                           
        version = "~> 0.9"                                                                                                                                                                                
      }
      flux = {
        source  = "fluxcd/flux"
        version = "~> 1.4"
      }                                                                                                                                                                                                   
    }                                                                                                                                                                                                     
  }   