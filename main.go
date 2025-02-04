/*


Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package main

import (
	"flag"
	"net/http"
	"os"

	uberzap "go.uber.org/zap"
	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	_ "k8s.io/client-go/plugin/pkg/client/auth/gcp"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"

	"github.com/ForgeRock/secret-agent/api/v1alpha1"
	"github.com/ForgeRock/secret-agent/controllers"
	// +kubebuilder:scaffold:imports
)

var (
	scheme   = runtime.NewScheme()
	setupLog = ctrl.Log.WithName("setup")
)

func init() {
	_ = clientgoscheme.AddToScheme(scheme)

	_ = v1alpha1.AddToScheme(scheme)
	// +kubebuilder:scaffold:scheme
}

func main() {
	var metricsAddr string
	var healthzAddr string
	var enableLeaderElection bool
	var certDir string
	var debug bool
	var lvl uberzap.AtomicLevel
	var cloudSecretsNamespace string

	flag.StringVar(&metricsAddr, "metrics-addr", ":8080", "The address the metric endpoint binds to. Set to 0 to disable metrics")
	flag.StringVar(&healthzAddr, "health-addr", ":8081", "The address the healthz/readyz endpoint binds to.")
	flag.BoolVar(&enableLeaderElection, "enable-leader-election", false,
		"Enable leader election for controller manager. "+
			"Enabling this will ensure there is only one active controller manager.")
	flag.StringVar(&certDir, "cert-dir", "/tmp/k8s-webhook-server/serving-certs",
		"Directory where to store/read the webhook certs. Defaults to /tmp/k8s-webhook-server/serving-certs")
	flag.BoolVar(&debug, "debug", false, "Set to true to enable debug")
	flag.StringVar(&cloudSecretsNamespace, "cloud-secrets-namespace", "",
		"Namespace where the cloud credentials secrets are located. Defaults to the SAC namespace")

	flag.Parse()
	if debug {
		lvl = uberzap.NewAtomicLevelAt(uberzap.DebugLevel)
	} else {
		lvl = uberzap.NewAtomicLevelAt(uberzap.InfoLevel)
	}
	ctrl.SetLogger(zap.New(zap.UseDevMode(false), zap.Level(&lvl)))

	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
		Scheme:                 scheme,
		MetricsBindAddress:     metricsAddr,
		Port:                   9443,
		LeaderElection:         enableLeaderElection,
		LeaderElectionID:       "f8e4a0d9.secrets.forgerock.io",
		CertDir:                certDir,
		HealthProbeBindAddress: healthzAddr,
	})
	if err != nil {
		setupLog.Error(err, "unable to start manager")
		os.Exit(1)
	}

	if err = (&controllers.SecretAgentConfigurationReconciler{
		Client:                mgr.GetClient(),
		Log:                   ctrl.Log.WithName("controllers").WithName("SecretAgentConfiguration"),
		Scheme:                mgr.GetScheme(),
		CloudSecretsNamespace: cloudSecretsNamespace,
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "unable to create controller", "controller", "SecretAgentConfiguration")
		os.Exit(1)
	}

	if os.Getenv("ENABLE_WEBHOOKS") != "false" {
		// Start creating certs for the webhooks
		setupLog.Info("Starting webhook related patches")
		if err := controllers.InitWebhookCertificates(certDir); err != nil {
			setupLog.Error(err, "Failed to init webhook certificates")
			os.Exit(1)
		}

		if err = (&v1alpha1.SecretAgentConfiguration{}).SetupWebhookWithManager(mgr); err != nil {
			setupLog.Error(err, "unable to create webhook", "webhook", "SecretAgentConfiguration")
			os.Exit(1)
		}
	}

	noop := func(_ *http.Request) error { return nil }
	if err = mgr.AddReadyzCheck("ready", noop); err != nil {
		setupLog.Error(err, "unable to add ready check")
		os.Exit(1)
	}
	if err = mgr.AddHealthzCheck("healthy", noop); err != nil {
		setupLog.Error(err, "unable to add health check")
		os.Exit(1)
	}

	// +kubebuilder:scaffold:builder

	setupLog.Info("starting manager")
	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		setupLog.Error(err, "problem running manager")
		os.Exit(1)
	}
}
