//
// Copyright (c) Microsoft Corporation
//
// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.
//

package com.microsoft.reacttestapp

import android.os.Bundle
import android.view.LayoutInflater
import android.widget.TextView
import androidx.recyclerview.widget.DividerItemDecoration
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.facebook.react.ReactActivity
import com.facebook.react.modules.systeminfo.ReactNativeVersion
import com.google.android.material.appbar.MaterialToolbar
import com.microsoft.reacttestapp.component.ComponentActivity
import com.microsoft.reacttestapp.component.ComponentBottomSheetDialogFragment
import com.microsoft.reacttestapp.component.ComponentListAdapter
import com.microsoft.reacttestapp.component.ComponentViewModel
import com.microsoft.reacttestapp.manifest.Component
import com.microsoft.reacttestapp.manifest.ManifestProvider
import com.microsoft.reacttestapp.react.BundleSource
import com.microsoft.reacttestapp.react.ReactBundleNameProvider
import com.microsoft.reacttestapp.react.TestAppReactNativeHost
import dagger.android.AndroidInjection
import javax.inject.Inject

class MainActivity : ReactActivity() {

    @Inject
    lateinit var manifestProvider: ManifestProvider

    @Inject
    lateinit var bundleNameProvider: ReactBundleNameProvider

    private var didInitialNavigation = false

    private val newComponentViewModel = { component: Component ->
        ComponentViewModel(
            component.appKey,
            component.displayName ?: component.appKey,
            component.initialProperties,
            component.presentationStyle
        )
    }

    private val session by lazy {
        Session(applicationContext)
    }

    private val startComponent: (ComponentViewModel) -> Unit = { component ->
        didInitialNavigation = true
        when (component.presentationStyle) {
            "modal" -> {
                ComponentBottomSheetDialogFragment
                    .newInstance(component)
                    .show(supportFragmentManager, ComponentBottomSheetDialogFragment.TAG)
            }
            else -> {
                startActivity(ComponentActivity.newIntent(this, component))
            }
        }
    }

    private val testAppReactNativeHost: TestAppReactNativeHost
        get() = reactNativeHost as TestAppReactNativeHost

    override fun onCreate(savedInstanceState: Bundle?) {
        AndroidInjection.inject(this)

        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        didInitialNavigation = savedInstanceState?.getBoolean("didInitialNavigation", false) == true

        val (manifest, checksum) = manifestProvider.fromResources()
            ?: throw IllegalStateException("app.json is not provided or TestApp is misconfigured")

        val index = if (manifest.components.count() == 1) 0 else session.lastOpenedComponent(checksum)
        index?.let {
            val component = newComponentViewModel(manifest.components[it])
            testAppReactNativeHost.addReactInstanceEventListener {
                if (!didInitialNavigation) {
                    startComponent(component)
                }
            }
        }

        setupToolbar(manifest.displayName)
        setupRecyclerView(manifest.components, checksum)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean("didInitialNavigation", didInitialNavigation)
        super.onSaveInstanceState(outState)
    }

    private fun reload(bundleSource: BundleSource) {
        testAppReactNativeHost.reload(this, bundleSource)
    }

    private fun setupRecyclerView(manifestComponents: List<Component>, manifestChecksum: String) {
        val components = manifestComponents.map(newComponentViewModel)
        findViewById<RecyclerView>(R.id.recyclerview).apply {
            layoutManager = LinearLayoutManager(context)
            adapter = ComponentListAdapter(
                LayoutInflater.from(context),
                components
            ) { component, index ->
                startComponent(component)
                session.storeComponent(index, manifestChecksum)
            }

            addItemDecoration(DividerItemDecoration(context, DividerItemDecoration.VERTICAL))
        }

        findViewById<TextView>(R.id.runtime_info).apply {
            text = resources.getString(
                R.string.runtime_info,
                ReactNativeVersion.VERSION["major"] as Int,
                ReactNativeVersion.VERSION["minor"] as Int,
                ReactNativeVersion.VERSION["patch"] as Int,
                reactInstanceManager.jsExecutorName
            )
        }
    }

    private fun setupToolbar(displayName: String) {
        val toolbar = findViewById<MaterialToolbar>(R.id.top_app_bar)

        toolbar.title = displayName
        toolbar.setOnMenuItemClickListener { menuItem ->
            when (menuItem.itemId) {
                R.id.load_embedded_js_bundle -> {
                    reload(BundleSource.Disk)
                    true
                }
                R.id.load_from_dev_server -> {
                    reload(BundleSource.Server)
                    true
                }
                R.id.remember_last_component -> {
                    val enable = !menuItem.isChecked
                    menuItem.isChecked = enable
                    session.shouldRememberLastComponent = enable
                    true
                }
                R.id.show_dev_options -> {
                    reactInstanceManager.devSupportManager.showDevOptionsDialog()
                    true
                }
                else -> false
            }
        }

        updateMenuItemState(toolbar, testAppReactNativeHost.source)
        testAppReactNativeHost.onBundleSourceChanged = {
            updateMenuItemState(toolbar, it)
        }
    }

    private fun updateMenuItemState(toolbar: MaterialToolbar, bundleSource: BundleSource) {
        toolbar.menu.apply {
            findItem(R.id.load_embedded_js_bundle).isEnabled = bundleNameProvider.bundleName != null
            findItem(R.id.remember_last_component).isChecked = session.shouldRememberLastComponent
            findItem(R.id.show_dev_options).isEnabled = bundleSource == BundleSource.Server
        }
    }
}
