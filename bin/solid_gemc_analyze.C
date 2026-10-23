// Schema-aware default plots for a solid_gemc run's out.root, run inside the
// container by `bin/solid-gemc-run analyze` (the ROOT counterpart of
// solid-gemc-analyze.py, which `analyze --python` runs on the host).
//
// Usage: root -l -b -q 'solid_gemc_analyze.C("<out.root>","<run-dir>",N)'
//
//   - TTrees:   one histogram per numeric branch (up to N), saved as
//               hist_<tree>_<branch>.svg plus a page in plots.pdf, with a
//               stats line per branch. Vector branches are flattened by
//               TTree::Draw. SVG/PDF because this ROOT build has no PNG writer.
//   - TH1/2/3:  listed, not re-plotted.
//   - neither:  reported as empty / non-standard.

void solid_gemc_analyze(const char* root_path, const char* run_dir, int max_plots = 12)
{
  TFile* f = TFile::Open(root_path);
  if (!f || f->IsZombie()) { printf("[analyze] cannot open %s\n", root_path); gSystem->Exit(1); }
  printf("[analyze] file: %s\n", root_path);

  TString pdf = TString::Format("%s/plots.pdf", run_dir);
  TCanvas c("c", "c", 800, 600);
  int plotted = 0, ntrees = 0;
  std::vector<TString> hists;

  TIter next(f->GetListOfKeys());
  while (TKey* key = (TKey*)next()) {
    TClass* cls = TClass::GetClass(key->GetClassName());
    if (!cls) continue;
    if (cls->InheritsFrom("TH1")) { hists.push_back(TString::Format("%s  %s", key->GetClassName(), key->GetName())); continue; }
    if (!cls->InheritsFrom("TTree")) continue;
    TTree* t = (TTree*)key->ReadObj();
    ntrees++;
    printf("[analyze]   tree %s: %lld entries, %d branches\n", t->GetName(), t->GetEntries(), t->GetListOfBranches()->GetEntries());
    if (t->GetEntries() == 0) continue;
    for (TObject* b : *t->GetListOfBranches()) {
      if (plotted >= max_plots) break;
      TString bname = b->GetName();
      TString hname = TString::Format("h_%s_%s", t->GetName(), bname.Data());
      Int_t old = gErrorIgnoreLevel; gErrorIgnoreLevel = kFatal;
      Long64_t n = t->Draw(TString::Format("%s>>%s", bname.Data(), hname.Data()), "", "goff");
      gErrorIgnoreLevel = old;
      TH1* h = (TH1*)gDirectory->Get(hname);
      if (n < 0 || !h) { printf("[analyze]     skip %s (not numeric)\n", bname.Data()); continue; }
      if (h->GetEntries() == 0) { printf("[analyze]     skip %s (no values)\n", bname.Data()); continue; }
      h->SetTitle(TString::Format("%s / %s;%s;count", t->GetName(), bname.Data(), bname.Data()));
      c.cd(); h->Draw();
      TString svg = TString::Format("%s/hist_%s_%s.svg", run_dir, t->GetName(), bname.Data());
      gErrorIgnoreLevel = kWarning;
      c.SaveAs(svg);
      if (plotted == 0) c.Print(pdf + "[", "pdf");
      c.Print(pdf, "pdf");
      gErrorIgnoreLevel = old;
      printf("[analyze]     %s: entries=%.0f mean=%g rms=%g under=%.0f over=%.0f -> %s\n",
             bname.Data(), h->GetEntries(), h->GetMean(), h->GetRMS(),
             h->GetBinContent(0), h->GetBinContent(h->GetNbinsX() + 1), gSystem->BaseName(svg));
      plotted++;
    }
    if (plotted >= max_plots) { printf("[analyze]   plot cap (%d) reached; pass a larger N for more.\n", max_plots); break; }
  }
  if (plotted > 0) {
    Int_t old = gErrorIgnoreLevel; gErrorIgnoreLevel = kWarning;
    c.Print(pdf + "]", "pdf");
    gErrorIgnoreLevel = old;
    printf("[analyze] %d plots -> %s\n", plotted, pdf.Data());
  }

  if (!hists.empty()) {
    printf("[analyze] file also contains %zu pre-built histograms (TH1/2/3).\n", hists.size());
    for (size_t i = 0; i < hists.size() && i < 10; i++) printf("[analyze]     %s\n", hists[i].Data());
    if (hists.size() > 10) printf("[analyze]     ... and %zu more.\n", hists.size() - 10);
    printf("[analyze]   (post-processed file; write a macro in the project dir to plot these.)\n");
  }
  if (ntrees == 0 && hists.empty()) printf("[analyze] no TTree or histogram objects found. Empty or non-standard file?\n");
  else if (ntrees == 0) printf("[analyze] no TTrees — file looks post-processed. Default plots skipped.\n");
  f->Close();
}
