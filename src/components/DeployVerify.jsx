/**
 * ============================================================================
 * src/components/DeployVerify.jsx – React component for deployment verification
 * CITATIONS:
 *   React: https://react.dev/ (v19)
 *   WebSocket API: https://developer.mozilla.org/en-US/docs/Web/API/WebSocket
 *   Three.js: https://threejs.org/ (v0.160+)
 *   OrbitControls: https://threejs.org/docs/#examples/en/controls/OrbitControls
 *   Lucide React: https://lucide.dev/guide/packages/lucide-react
 *   WebSocket RFC: https://datatracker.ietf.org/doc/html/rfc6455
 *
 * Integration: This component connects to the FastAPI WebSocket endpoint
 *              (/ws/deploy/verify) and streams live logs, updates a 3D pipeline
 *              visualization, and surfaces evidence links.
 * Rules: #1,#7,#8,#9,#16,#30,#32,#38,#41,#48,#49,#50,#52,#53,#54,#55
 * ============================================================================
 */
import React, { useState, useEffect, useRef, useCallback } from 'react';
import { RefreshCw, CheckCircle2, XCircle, Clock, ExternalLink, Loader2 } from 'lucide-react';

// Three.js is optional – import only if installed
// Ref: https://threejs.org/docs/#manual/en/introduction/Installation
let THREE = null;
let OrbitControls = null;
try {
  THREE = require('three');
  // Ref: https://threejs.org/docs/#examples/en/controls/OrbitControls
  OrbitControls = require('three/examples/jsm/controls/OrbitControls').OrbitControls;
} catch (e) {
  // Three.js not installed – fallback to simple status display
}

/**
 * DeployVerify – Main component.
 * Props:
 *   @param {string} githubOwner – GitHub owner (username)
 *   @param {string} githubRepo  – GitHub repository name
 */
const DeployVerify = ({ githubOwner, githubRepo }) => {
  const [logs, setLogs] = useState([]);
  const [status, setStatus] = useState('idle'); // idle | running | success | failure
  const [ws, setWs] = useState(null);
  const [error, setError] = useState(null);
  const [evidenceLinks, setEvidenceLinks] = useState(null);
  const mountRef = useRef(null);       // Three.js container
  const sceneRef = useRef(null);       // Three.js scene objects
  const logEndRef = useRef(null);      // Scroll anchor for logs

  // --------------------------------------------------------------------------
  // Three.js Scene Setup (optional)
  // Ref: https://threejs.org/docs/#manual/en/introduction/Creating-a-scene
  // Ref: https://threejs.org/docs/#manual/en/introduction/Animation-loop
  // --------------------------------------------------------------------------
  useEffect(() => {
    if (!mountRef.current || !THREE || !OrbitControls) return;
    const container = mountRef.current;
    const width = container.clientWidth || 600;
    const height = 300;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0x0f172a);
    const camera = new THREE.PerspectiveCamera(45, width / height, 0.1, 100);
    camera.position.set(8, 4, 12);
    camera.lookAt(0, 0, 0);

    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setSize(width, height);
    renderer.shadowMap.enabled = true;
    container.appendChild(renderer.domElement);

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.dampingFactor = 0.05;

    // Pipeline nodes (Local → GitHub → Actions → Pages)
    const nodes = [
      { name: 'Local', x: -6, y: 0, z: 0, color: 0x3b82f6 },
      { name: 'GitHub', x: -2, y: 0, z: 0, color: 0x8b5cf6 },
      { name: 'Actions', x: 2, y: 0, z: 0, color: 0xf59e0b },
      { name: 'Pages', x: 6, y: 0, z: 0, color: 0x10b981 },
    ];

    const sphereGroup = new THREE.Group();
    const spheres = [];
    nodes.forEach((node, i) => {
      const geometry = new THREE.SphereGeometry(0.8, 32, 32);
      const material = new THREE.MeshStandardMaterial({
        color: node.color,
        emissive: node.color,
        emissiveIntensity: 0.2,
      });
      const sphere = new THREE.Mesh(geometry, material);
      sphere.position.set(node.x, node.y, node.z);
      sphere.userData = { index: i, name: node.name, status: 'idle' };
      sphereGroup.add(sphere);
      spheres.push(sphere);

      // Connector lines
      if (i > 0) {
        const prev = nodes[i - 1];
        const points = [
          new THREE.Vector3(prev.x, 0, 0),
          new THREE.Vector3(node.x, 0, 0),
        ];
        const lineGeometry = new THREE.BufferGeometry().setFromPoints(points);
        const lineMaterial = new THREE.LineBasicMaterial({ color: 0x475569 });
        const line = new THREE.Line(lineGeometry, lineMaterial);
        sphereGroup.add(line);
      }
    });
    scene.add(sphereGroup);

    // Lighting (ambient + directional)
    scene.add(new THREE.AmbientLight(0x404060));
    const dirLight = new THREE.DirectionalLight(0xffffff, 1);
    dirLight.position.set(5, 10, 7);
    scene.add(dirLight);
    scene.add(new THREE.DirectionalLight(0x8888ff, 0.5));

    sceneRef.current = { scene, camera, renderer, controls, sphereGroup, spheres, nodes };

    // Animation loop
    const animate = () => {
      requestAnimationFrame(animate);
      controls.update();
      renderer.render(scene, camera);
    };
    animate();

    // Resize handler
    const handleResize = () => {
      const w = container.clientWidth || 600;
      camera.aspect = w / height;
      camera.updateProjectionMatrix();
      renderer.setSize(w, height);
    };
    window.addEventListener('resize', handleResize);

    return () => {
      window.removeEventListener('resize', handleResize);
      if (container && renderer.domElement) {
        container.removeChild(renderer.domElement);
      }
      renderer.dispose();
    };
  }, []);

  // --------------------------------------------------------------------------
  // Update Three.js visualization based on log lines
  // --------------------------------------------------------------------------
  const updateVisualization = useCallback((logLine) => {
    if (!sceneRef.current) return;
    const { spheres, nodes } = sceneRef.current;
    const lower = logLine.toLowerCase();
    let activeIndex = -1;
    if (lower.includes('push')) activeIndex = 0;
    else if (lower.includes('github') || lower.includes('workflow')) activeIndex = 1;
    else if (lower.includes('actions') || lower.includes('build')) activeIndex = 2;
    else if (lower.includes('pages') || lower.includes('deploy')) activeIndex = 3;

    spheres.forEach((sphere, idx) => {
      const baseColor = nodes[idx].color;
      if (idx === activeIndex) {
        sphere.material.color.setHex(0x22d3ee);
        sphere.material.emissive.setHex(0x22d3ee);
        sphere.material.emissiveIntensity = 0.8;
      } else if (idx < activeIndex) {
        sphere.material.color.setHex(0x10b981);
        sphere.material.emissive.setHex(0x10b981);
        sphere.material.emissiveIntensity = 0.3;
      } else {
        sphere.material.color.setHex(baseColor);
        sphere.material.emissive.setHex(baseColor);
        sphere.material.emissiveIntensity = 0.2;
      }
    });
  }, []);

  // --------------------------------------------------------------------------
  // WebSocket Connection
  // Ref: https://developer.mozilla.org/en-US/docs/Web/API/WebSocket
  // --------------------------------------------------------------------------
  const startVerification = useCallback(() => {
    setStatus('running');
    setLogs([]);
    setError(null);
    setEvidenceLinks(null);

    const wsUrl = `${window.location.protocol === 'https:' ? 'wss:' : 'ws:'}//${window.location.host}/ws/deploy/verify`;
    const socket = new WebSocket(wsUrl);
    setWs(socket);

    socket.onopen = () => {
      socket.send(JSON.stringify({
        owner: githubOwner,
        repo: githubRepo,
        branch: 'master',
      }));
    };

    socket.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        if (data.type === 'log') {
          setLogs(prev => [...prev, data.data]);
          updateVisualization(data.data);
        } else if (data.type === 'stderr') {
          setLogs(prev => [...prev, `[stderr] ${data.data}`]);
        } else if (data.type === 'done') {
          setStatus(data.success ? 'success' : 'failure');
          if (data.success) {
            // Extract evidence links from logs (raw GitHub URLs)
            const logText = logs.join('\n');
            const logMatch = logText.match(/https:\/\/raw\.githubusercontent\.com\/[^\s]+\.txt/);
            const domMatch = logText.match(/https:\/\/raw\.githubusercontent\.com\/[^\s]+\.html/);
            setEvidenceLinks({
              logs: logMatch ? logMatch[0] : null,
              rendered: domMatch ? domMatch[0] : null,
            });
          }
          socket.close();
        } else if (data.type === 'error') {
          setStatus('failure');
          setError(data.message);
          socket.close();
        }
      } catch (err) {
        setError(`Parse error: ${err.message}`);
      }
    };

    socket.onerror = (err) => {
      setStatus('failure');
      setError(`WebSocket error: ${err.message || 'Unknown error'}`);
    };

    socket.onclose = () => {
      setWs(null);
    };
  }, [githubOwner, githubRepo, logs, updateVisualization]);

  const stopVerification = () => {
    if (ws) ws.close();
    setStatus('idle');
  };

  // Auto-scroll logs to bottom
  useEffect(() => {
    if (logEndRef.current) {
      logEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [logs]);

  // --------------------------------------------------------------------------
  // UI Render Helpers
  // --------------------------------------------------------------------------
  const getStatusIcon = () => {
    if (status === 'idle') return <Clock className="text-slate-400" size={20} />;
    if (status === 'running') return <Loader2 className="text-yellow-400 animate-spin" size={20} />;
    if (status === 'success') return <CheckCircle2 className="text-emerald-400" size={20} />;
    if (status === 'failure') return <XCircle className="text-red-400" size={20} />;
    return <Clock className="text-slate-400" size={20} />;
  };

  const getStatusText = () => {
    if (status === 'idle') return 'Ready';
    if (status === 'running') return 'Running...';
    if (status === 'success') return 'Verified';
    if (status === 'failure') return 'Failed';
    return status;
  };

  const getStatusColor = () => {
    if (status === 'idle') return 'bg-slate-700 text-slate-300';
    if (status === 'running') return 'bg-yellow-500/20 text-yellow-400 animate-pulse';
    if (status === 'success') return 'bg-emerald-500/20 text-emerald-400';
    if (status === 'failure') return 'bg-red-500/20 text-red-400';
    return 'bg-slate-700 text-slate-300';
  };

  // --------------------------------------------------------------------------
  // Component Render
  // --------------------------------------------------------------------------
  return (
    <div className="bg-slate-900 border border-slate-800 rounded-xl p-6 mt-6">
      <h3 className="text-lg font-semibold mb-4 flex items-center gap-2">
        <RefreshCw className="text-purple-400" /> Deployment & Verification
      </h3>

      {/* Three.js visualization container */}
      <div
        ref={mountRef}
        className="w-full h-64 bg-slate-950 rounded-lg border border-slate-800 mb-4 overflow-hidden"
      >
        {!THREE && (
          <div className="flex items-center justify-center h-full text-slate-500 text-sm">
            Three.js not installed – install with: npm install three
          </div>
        )}
      </div>

      {/* Status + controls */}
      <div className="flex flex-wrap items-center gap-4 mb-4">
        <div className="flex items-center gap-2">
          <span className={`px-3 py-1 rounded-full text-sm font-medium ${getStatusColor()}`}>
            {getStatusIcon()} {getStatusText()}
          </span>
          <span className="text-xs text-slate-400">Pipeline: Local → GitHub → Actions → Pages</span>
        </div>
        <div className="flex gap-2 ml-auto">
          <button
            onClick={startVerification}
            disabled={status === 'running'}
            className={`px-4 py-2 rounded-lg text-sm font-medium transition ${
              status === 'running'
                ? 'bg-slate-700 text-slate-400 cursor-not-allowed'
                : 'bg-blue-600 hover:bg-blue-500 text-white'
            }`}
          >
            {status === 'running' ? 'Processing...' : 'Run Verification'}
          </button>
          {status === 'running' && (
            <button
              onClick={stopVerification}
              className="text-red-400 hover:text-red-300 text-sm px-3 py-2"
            >
              Cancel
            </button>
          )}
        </div>
      </div>

      {/* Error message */}
      {error && (
        <div className="mb-3 p-3 bg-red-950/50 border border-red-800 rounded-lg text-red-300 text-sm">
          {error}
        </div>
      )}

      {/* Live logs terminal */}
      <div className="bg-slate-950 rounded-lg border border-slate-800 p-3 max-h-48 overflow-y-auto font-mono text-xs text-slate-300">
        {logs.length === 0 ? (
          <span className="text-slate-500">Click "Run Verification" to start</span>
        ) : (
          logs.map((line, i) => (
            <div key={i} className="whitespace-pre-wrap border-b border-slate-800/30 py-0.5">
              {line}
            </div>
          ))
        )}
        <div ref={logEndRef} />
      </div>

      {/* Evidence links */}
      {evidenceLinks && (
        <div className="mt-4 text-xs text-slate-400 border-t border-slate-800 pt-3">
          <span className="font-medium text-slate-300">Evidence Links:</span>
          <div className="flex flex-wrap gap-3 mt-1">
            {evidenceLinks.logs && (
              <a href={evidenceLinks.logs} target="_blank" rel="noopener noreferrer" className="text-blue-400 hover:underline flex items-center gap-1">
                Workflow Logs <ExternalLink size={12} />
              </a>
            )}
            {evidenceLinks.rendered && (
              <a href={evidenceLinks.rendered} target="_blank" rel="noopener noreferrer" className="text-blue-400 hover:underline flex items-center gap-1">
                Rendered DOM <ExternalLink size={12} />
              </a>
            )}
            <a href={`https://${githubOwner}.github.io/${githubRepo}/`} target="_blank" rel="noopener noreferrer" className="text-blue-400 hover:underline flex items-center gap-1">
              Live Site <ExternalLink size={12} />
            </a>
          </div>
        </div>
      )}
    </div>
  );
};

export default DeployVerify;
