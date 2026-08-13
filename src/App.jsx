import React, { useState } from 'react';
import { Terminal, ShieldCheck, Download, Cpu, Database, Server, RefreshCw, CheckCircle2, Github, Box, BookOpen, BrainCircuit, Sparkles, Wrench, MessageSquare } from 'lucide-react';

const TOOLS = [
  { key: 'karakeep', name: 'Karakeep', desc: 'Bookmark manager with AI tagging', icon: BookOpen, color: 'text-amber-400' },
  { key: 'ggml', name: 'GGML', desc: 'Tensor library (source build)', icon: BrainCircuit, color: 'text-purple-400' },
  { key: 'llama_cpp', name: 'llama.cpp', desc: 'Inference engine (CUDA/Metal)', icon: Cpu, color: 'text-cyan-400' },
  { key: 'harper', name: 'Harper', desc: 'Grammar checker (Rust)', icon: Sparkles, color: 'text-pink-400' },
  { key: 'languagetool', name: 'LanguageTool', desc: 'Multi-lang grammar (optional)', icon: Wrench, color: 'text-orange-400' },
  { key: 'open_notebook', name: 'Open Notebook', desc: 'NotebookLM alternative', icon: MessageSquare, color: 'text-emerald-400' },
  { key: 'librechat', name: 'LibreChat', desc: 'AI chat (multi-provider)', icon: Server, color: 'text-blue-400' },
];

export default function App() {
  const [selected, setSelected] = useState({ karakeep: true, ggml: true, llama_cpp: true, harper: false, open_notebook: false, librechat: false });
  const [backendDb, setBackendDb] = useState('postgresql');
  const [githubOwner, setGithubOwner] = useState('swipswaps');
  const [githubRepo, setGithubRepo] = useState('local-ops-hub');
  const [downloaded, setDownloaded] = useState(false);

  const toggle = (key) => setSelected(prev => ({ ...prev, [key]: !prev[key] }));

  const handleDownload = () => {
    const toolsArg = Object.entries(selected).filter(([,v]) => v).map(([k]) => k).join(',');
    const shellScript = `#!/usr/bin/env bash
# Local Ops Hub Installer Bootstrap
export GITHUB_OWNER="${githubOwner}"
export GITHUB_REPO="${githubRepo}"
export DB_BACKEND="${backendDb}"
export SELECTED_TOOLS="${toolsArg}"

echo "Downloading installer..."
curl -fsSL -o local_ops_installer.py "https://raw.githubusercontent.com/${githubOwner}/${githubRepo}/main/scripts/local_ops_installer.py" || {
  echo "Download failed. Check internet or repo name."
  exit 1
}
chmod +x local_ops_installer.py
python3 local_ops_installer.py
`;
    const blob = new Blob([shellScript], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'install_local_ops.sh';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setDownloaded(true);
  };

  return (
    <div className="max-w-6xl mx-auto p-6">
      <header className="flex justify-between items-center mb-8 border-b border-slate-800 pb-6">
        <div>
          <h1 className="text-3xl font-bold flex items-center gap-3">
            <Cpu className="text-blue-500" /> Local Ops & Architecture Hub
          </h1>
          <p className="text-slate-400 mt-1">Advanced local operations, system auditing, and modular stack management.</p>
        </div>
        <div className="flex items-center gap-2 bg-slate-900 border border-slate-800 px-4 py-2 rounded-lg text-sm">
          <ShieldCheck className="text-emerald-400" />
          <span>README.md</span>
        </div>
      </header>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
        <div className="bg-slate-900 border border-slate-800 rounded-xl p-6">
          <h2 className="text-xl font-semibold mb-4 flex items-center gap-2"><Terminal className="text-indigo-400" /> 1. System Audit</h2>
          <p className="text-slate-400 text-sm mb-4">Download the bootstrap script. It fetches the full installer from your repo and runs it interactively.</p>
          <button onClick={handleDownload} className="w-full bg-blue-600 hover:bg-blue-500 text-white font-medium py-2.5 px-4 rounded-lg flex items-center justify-center gap-2 transition">
            <Download size={18} /> Download Bootstrap Script
          </button>
          {downloaded && <p className="text-emerald-400 text-xs mt-2 flex items-center gap-1"><CheckCircle2 size={14} /> Script downloaded.</p>}
        </div>

        <div className="bg-slate-900 border border-slate-800 rounded-xl p-6">
          <h2 className="text-xl font-semibold mb-4 flex items-center gap-2"><Github className="text-slate-300" /> GitHub Config</h2>
          <div className="space-y-3 text-sm">
            <div>
              <label className="block text-slate-400 mb-1">Owner</label>
              <input type="text" value={githubOwner} onChange={e => setGithubOwner(e.target.value)} className="w-full bg-slate-950 border border-slate-700 rounded px-3 py-2 text-slate-200" />
            </div>
            <div>
              <label className="block text-slate-400 mb-1">Repo</label>
              <input type="text" value={githubRepo} onChange={e => setGithubRepo(e.target.value)} className="w-full bg-slate-950 border border-slate-700 rounded px-3 py-2 text-slate-200" />
            </div>
          </div>
        </div>

        <div className="bg-slate-900 border border-slate-800 rounded-xl p-6">
          <h2 className="text-xl font-semibold mb-4 flex items-center gap-2"><Database className="text-amber-400" /> Backend DB</h2>
          <div className="space-y-3 text-sm">
            <label className="flex items-center gap-2 cursor-pointer">
              <input type="radio" name="db" value="sqlite" checked={backendDb === 'sqlite'} onChange={e => setBackendDb(e.target.value)} className="text-blue-600" />
              <span>SQLite (Lightweight)</span>
            </label>
            <label className="flex items-center gap-2 cursor-pointer">
              <input type="radio" name="db" value="postgresql" checked={backendDb === 'postgresql'} onChange={e => setBackendDb(e.target.value)} className="text-blue-600" />
              <span>PostgreSQL (Docker)</span>
            </label>
          </div>
        </div>
      </div>

      <div className="bg-slate-900 border border-slate-800 rounded-xl p-6 mb-8">
        <h2 className="text-xl font-semibold mb-4 flex items-center gap-2"><Box className="text-emerald-400" /> 2. Stack Selection</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {TOOLS.map(tool => {
            const Icon = tool.icon;
            return (
              <label key={tool.key} className="flex items-start gap-3 bg-slate-950 border border-slate-800 rounded-lg p-4 cursor-pointer hover:border-slate-600 transition">
                <input type="checkbox" checked={selected[tool.key]} onChange={() => toggle(tool.key)} className="mt-1 rounded bg-slate-800 border-slate-700 text-blue-600" />
                <div className="flex-1">
                  <div className="flex items-center gap-2 font-medium"><Icon size={16} className={tool.color} /> {tool.name}</div>
                  <p className="text-slate-500 text-xs mt-1">{tool.desc}</p>
                </div>
              </label>
            );
          })}
        </div>
      </div>

      <div className="bg-slate-900 border border-slate-800 rounded-xl p-6">
        <h3 className="text-lg font-semibold mb-3 flex items-center gap-2"><RefreshCw className="text-purple-400" /> Operations Dashboard</h3>
        <p className="text-slate-400 text-sm mb-4">Backend telemetry, rollback, and recovery operations.</p>
        <div className="bg-slate-950 p-4 rounded-lg font-mono text-xs text-slate-300 overflow-x-auto border border-slate-800">
          <p className="text-emerald-400"># Backend: http://localhost:8000</p>
          <p className="text-slate-500"># Selected: {Object.entries(selected).filter(([,v])=>v).map(([k])=>k).join(', ') || 'none'}</p>
          <p className="text-slate-500"># Database: {backendDb}</p>
          <p className="text-slate-500"># GitHub: {githubOwner}/{githubRepo}</p>
        </div>
      </div>
    </div>
  );
}
