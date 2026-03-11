import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.trainingos.app',
  appName: 'TrainingOS',
  webDir: 'www',

  // The app loads content from the deployed Flask/Vercel backend.
  server: {
    url: 'https://training-os-rho.vercel.app',
    cleartext: false,
    allowNavigation: ['training-os-rho.vercel.app'],
  },

  plugins: {
    SplashScreen: {
      launchShowDuration: 2000,
      launchAutoHide: true,
      backgroundColor: '#0f0f17',
      androidSplashResourceName: 'splash',
      splashFullScreen: true,
      splashImmersive: true,
      showSpinner: false,
    },
    StatusBar: {
      style: 'Dark',
      backgroundColor: '#0f0f17',
      overlaysWebView: false,
    },
  },

  ios: {
    path: 'mobile/ios',
    // Allows the WKWebView to occupy the full screen including safe areas
    contentInset: 'always',
    allowsLinkPreview: false,
    scrollEnabled: true,
    backgroundColor: '#0f0f17',
  },
};

export default config;
