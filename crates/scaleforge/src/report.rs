//! JSON serialisation of job reports.

use sf_analysis::AnalysisReport;
use sf_core::json::{Number, Object, Value};

use crate::pipeline::JobReport;

fn num(v: f64) -> Value {
    Number::from_f64(v).map(Value::Number).unwrap_or(Value::Null)
}

/// The analysis report as JSON.
pub fn analysis_json(a: &AnalysisReport) -> Value {
    let mut o = Object::new();
    o.insert("width", a.width);
    o.insert("height", a.height);
    let m = |v: f64, est: &str| {
        let mut x = Object::new();
        x.insert("value", num(v));
        x.insert("estimator", est);
        Value::from(x)
    };
    o.insert("noise_sigma", m(a.noise_sigma.value, a.noise_sigma.estimator));
    o.insert(
        "noise_by_level",
        a.noise_by_level.iter().map(|&(l, s)| Value::from(vec![num(l), num(s)])).collect::<Vec<_>>(),
    );
    o.insert("jpeg_quality", a.jpeg_quality.as_ref().map_or(Value::Null, |q| m(q.value, q.estimator)));
    o.insert("blockiness", m(a.blockiness.value, a.blockiness.estimator));
    o.insert("edge_width_px", a.edge_width.as_ref().map_or(Value::Null, |e| m(e.value, e.estimator)));
    let mut e = Object::new();
    e.insert("p1", num(a.exposure.p1));
    e.insert("p50", num(a.exposure.p50));
    e.insert("p99", num(a.exposure.p99));
    e.insert("clipped_dark", num(a.exposure.clipped_dark));
    e.insert("clipped_bright", num(a.exposure.clipped_bright));
    o.insert("exposure", e);
    o.insert("rms_contrast", num(a.contrast));
    o.insert(
        "colour_balance",
        a.color_balance.map_or(Value::Null, |(r, b)| Value::from(vec![num(r), num(b)])),
    );
    o.insert("texture_density", num(a.texture_density));
    o.insert(
        "unavailable",
        a.unavailable
            .iter()
            .map(|(q, why)| {
                let mut x = Object::new();
                x.insert("quantity", *q);
                x.insert("reason", *why);
                Value::from(x)
            })
            .collect::<Vec<_>>(),
    );
    Value::from(o)
}

/// The job report as JSON.
pub fn job_json(r: &JobReport) -> Value {
    let mut o = Object::new();
    o.insert("input", r.input.display().to_string());
    o.insert("output", r.output.display().to_string());
    o.insert("input_size", vec![Value::from(r.input_size.0), Value::from(r.input_size.1)]);
    o.insert("output_size", vec![Value::from(r.output_size.0), Value::from(r.output_size.1)]);
    o.insert("output_bytes", r.output_bytes);
    if let Some((name, prov, scope)) = &r.model {
        let mut m = Object::new();
        m.insert("name", name.as_str());
        m.insert("provenance", prov.as_str());
        m.insert("licence_scope", scope.as_str());
        o.insert("model", m);
    } else {
        o.insert("model", Value::Null);
    }
    o.insert("analysis", analysis_json(&r.analysis));
    o.insert(
        "decisions",
        r.decisions
            .iter()
            .map(|d| {
                let mut x = Object::new();
                x.insert("parameter", d.parameter);
                x.insert("value", d.value.as_str());
                x.insert("source", d.source.name());
                x.insert("rule", d.rule);
                x.insert("evidence", d.evidence.as_str());
                Value::from(x)
            })
            .collect::<Vec<_>>(),
    );
    let mut qc = Object::new();
    qc.insert("passed", r.qc.passed());
    qc.insert(
        "checks",
        r.qc.checks
            .iter()
            .map(|c| {
                let mut x = Object::new();
                x.insert("name", c.name);
                x.insert("value", num(c.value));
                x.insert("limit", num(c.limit));
                x.insert("pass", c.pass);
                x.insert("unit", c.unit);
                Value::from(x)
            })
            .collect::<Vec<_>>(),
    );
    qc.insert("notes", r.qc.notes.iter().map(|n| Value::from(n.as_str())).collect::<Vec<_>>());
    o.insert("qc", qc);
    o.insert(
        "compliance",
        r.compliance.as_ref().map_or(Value::Null, |c| {
            let mut x = Object::new();
            x.insert("profile", c.profile.as_str());
            x.insert("verdict", c.verdict);
            x.insert(
                "rules",
                c.rules
                    .iter()
                    .map(|(rule, ok, detail)| {
                        let mut y = Object::new();
                        y.insert("rule", rule.as_str());
                        y.insert("ok", *ok);
                        y.insert("detail", detail.as_str());
                        Value::from(y)
                    })
                    .collect::<Vec<_>>(),
            );
            x.insert("warnings", c.warnings.iter().map(|w| Value::from(w.as_str())).collect::<Vec<_>>());
            x.insert("ai_disclosure", c.ai_disclosure.as_str());
            Value::from(x)
        }),
    );
    let mut t = Object::new();
    for (k, v) in &r.timings_ms {
        t.insert(*k, num(*v));
    }
    o.insert("timings_ms", t);
    o.insert("peak_device_bytes", r.peak_device_bytes);
    o.insert("warnings", r.warnings.iter().map(|w| Value::from(w.as_str())).collect::<Vec<_>>());
    Value::from(o)
}
