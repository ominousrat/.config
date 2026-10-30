source /usr/share/cachyos-fish-config/cachyos-config.fish

# overwrite greeting
# potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end

set -gx HSA_OVERRIDE_GFX_VERSION 11.5.1
set -gx HSA_ENABLE_SDMA 0

# Vulkan Variables
set -x VULKAN_SDK $HOME/vulkan/1.4.357.0/x86_64
set -x PATH $VULKAN_SDK/bin $PATH
set -x LD_LIBRARY_PATH $VULKAN_SDK/lib $LD_LIBRARY_PATH

# Added by LM Studio CLI (lms)
set -gx PATH $PATH /home/rat/.lmstudio/bin
# End of LM Studio CLI section
