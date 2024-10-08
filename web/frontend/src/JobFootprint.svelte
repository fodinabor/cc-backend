<script context="module">
  export function findJobThresholds(job, metricConfig, subClusterConfig) {
    if (!job || !metricConfig || !subClusterConfig) {
      console.warn("Argument missing for findJobThresholds!");
      return null;
    }

    const subclusterThresholds = metricConfig.subClusters.find(
      (sc) => sc.name == subClusterConfig.name,
    );
    const defaultThresholds = {
      peak: subclusterThresholds
        ? subclusterThresholds.peak
        : metricConfig.peak,
      normal: subclusterThresholds
        ? subclusterThresholds.normal
        : metricConfig.normal,
      caution: subclusterThresholds
        ? subclusterThresholds.caution
        : metricConfig.caution,
      alert: subclusterThresholds
        ? subclusterThresholds.alert
        : metricConfig.alert,
    };

    // Job_Exclusivity does not matter, only aggregation
    if (metricConfig.aggregation === "avg") {
      return defaultThresholds;
    } else if (metricConfig.aggregation === "sum") {
      const jobFraction =
        job.numHWThreads / subClusterConfig.topology.node.length;
      return {
        peak: round(defaultThresholds.peak * jobFraction, 0),
        normal: round(defaultThresholds.normal * jobFraction, 0),
        caution: round(defaultThresholds.caution * jobFraction, 0),
        alert: round(defaultThresholds.alert * jobFraction, 0),
      };
    } else {
      console.warn(
        "Missing or unkown aggregation mode (sum/avg) for metric:",
        metricConfig,
      );
      return defaultThresholds;
    }
  }
</script>

<script>
  import { getContext } from "svelte";
  import {
    Card,
    CardHeader,
    CardTitle,
    CardBody,
    Progress,
    Icon,
    Tooltip,
  } from "@sveltestrap/sveltestrap";
  import { mean, round } from "mathjs";

  export let job;
  export let jobMetrics;
  export let view = "job";
  export let width = "auto";

  const clusters = getContext("clusters");
  const subclusterConfig = clusters
    .find((c) => c.name == job.cluster)
    .subClusters.find((sc) => sc.name == job.subCluster);

  const footprintMetrics =
    job.numAcc !== 0
      ? job.exclusive !== 1 // GPU
        ? ["acc_utilization", "acc_mem_used", "nv_sm_clock", "nv_mem_util"] // Shared
        : ["acc_utilization", "acc_mem_used", "nv_sm_clock", "nv_mem_util"] // Exclusive
      : (job.exclusive !== 1) // CPU Only
        ? ["flops_any", "mem_used"] // Shared
        : ["cpu_load", "flops_any", "mem_used", "mem_bw"]; // Exclusive

  const footprintData = footprintMetrics.map((fm) => {
    // Unit
    const fmc = getContext("metrics")(job.cluster, fm);
    if(fmc === undefined) {
      return {
        name: fm,
        unit: "s",
        avg: 0,
        max: 0,
        color: "info",
        message: "Metric not configured.",
        impact: 0,
      };
    }

    let unit = "";
    if (fmc?.unit?.base) unit = fmc.unit.prefix + fmc.unit.base;

    // Threshold / -Differences
    const fmt = findJobThresholds(job, fmc, subclusterConfig);
    if (fm === "flops_any") fmt.peak = round(fmt.peak * 0.85, 0);

    // Value: Primarily use backend sourced avgs from job.*, secondarily calculate/read from metricdata
    // Exclusivity does not matter
    let mv = 0.0;
    if (fmc.aggregation === "avg") {
      if (fm === "cpu_load" && job.loadAvg !== 0) {
        mv = round(job.loadAvg, 2);
      } else if (fm === "flops_any" && job.flopsAnyAvg !== 0) {
        mv = round(job.flopsAnyAvg, 2);
      } else if (fm === "mem_bw" && job.memBwAvg !== 0) {
        mv = round(job.memBwAvg, 2);
      } else {
        // Calculate Avg from jobMetrics
        const jm = jobMetrics.find((jm) => jm.name === fm && jm.scope === "node");
        if (jm?.metric?.statisticsSeries) {
          const noNan = jm.metric.statisticsSeries.mean.filter(function (val) {
            return val != null;
          });
          mv = round(mean(noNan), 2);
        } else if (jm?.metric?.series?.length > 1) {
          const avgs = jm.metric.series.map((jms) => jms.statistics.avg);
          mv = round(mean(avgs), 2);
        } else if (jm?.metric?.series) {
          mv = round(jm.metric.series[0].statistics.avg, 2);
        }
      }
    } else if (fmc.aggregation === "sum") {
        // Calculate Sum from jobMetrics: Sum all node averages
        const jm = jobMetrics.find((jm) => jm.name === fm && jm.scope === "node");
        if (jm?.metric?.series?.length > 1) { // More than 1 node
          const avgs = jm.metric.series.map((jms) => jms.statistics.avg);
          mv = round(avgs.reduce((a, b) => a + b, 0));
        } else if (jm?.metric?.series) {
          mv = round(jm.metric.series[0].statistics.avg, 2);
        }
    } else {
      console.warn(
        "Missing or unkown aggregation mode (sum/avg) for metric:",
        metricConfig,
      );
    }

    // Define basic data
    const fmBase = {
      name: fm,
      unit: unit,
      avg: mv,
      max: fmt.peak,
    };

    if (evalFootprint(fm, mv, fmt, "alert")) {
      return {
        ...fmBase,
        color: "danger",
        message: `Metric average way ${fm === "mem_used" ? "above" : "below"} expected normal thresholds.`,
        impact: 3,
      };
    } else if (evalFootprint(fm, mv, fmt, "caution")) {
      return {
        ...fmBase,
        color: "warning",
        message: `Metric average ${fm === "mem_used" ? "above" : "below"} expected normal thresholds.`,
        impact: 2,
      };
    } else if (evalFootprint(fm, mv, fmt, "normal")) {
      return {
        ...fmBase,
        color: "success",
        message: "Metric average within expected thresholds.",
        impact: 1,
      };
    } else if (evalFootprint(fm, mv, fmt, "peak")) {
      return {
        ...fmBase,
        color: "info",
        message:
          "Metric average above expected normal thresholds: Check for artifacts recommended.",
        impact: 0,
      };
    } else {
      return {
        ...fmBase,
        color: "secondary",
        message:
          "Metric average above expected peak threshold: Check for artifacts!",
        impact: -1,
      };
    }
  });

  function evalFootprint(metric, mean, thresholds, level) {
    // mem_used has inverse logic regarding threshold levels, notify levels triggered if mean > threshold
    switch (level) {
      case "peak":
        if (metric === "mem_used")
          return false; // mem_used over peak -> return false to trigger impact -1
        else return mean <= thresholds.peak && mean > thresholds.normal;
      case "alert":
        if (metric === "mem_used")
          return mean <= thresholds.peak && mean >= thresholds.alert;
        else return mean <= thresholds.alert && mean >= 0;
      case "caution":
        if (metric === "mem_used")
          return mean < thresholds.alert && mean >= thresholds.caution;
        else return mean <= thresholds.caution && mean > thresholds.alert;
      case "normal":
        if (metric === "mem_used")
          return mean < thresholds.caution && mean >= 0;
        else return mean <= thresholds.normal && mean > thresholds.caution;
      default:
        return false;
    }
  }
</script>

<Card class="h-auto mt-1" style="width: {width}px;">
  {#if view === "job"}
    <CardHeader>
      <CardTitle class="mb-0 d-flex justify-content-center">
        Core Metrics Footprint
      </CardTitle>
    </CardHeader>
  {/if}
  <CardBody>
    {#each footprintData as fpd, index}
      <div class="mb-1 d-flex justify-content-between">
        <div>&nbsp;<b>{fpd.name}</b></div>
        <!-- For symmetry, see below ...-->
        <div
          class="cursor-help d-inline-flex"
          id={`footprint-${job.jobId}-${index}`}
        >
          <div class="mx-1">
            <!-- Alerts Only -->
            {#if fpd.impact === 3 || fpd.impact === -1}
              <Icon name="exclamation-triangle-fill" class="text-danger" />
            {:else if fpd.impact === 2}
              <Icon name="exclamation-triangle" class="text-warning" />
            {/if}
            <!-- Emoji for all states-->
            {#if fpd.impact === 3}
              <Icon name="emoji-frown" class="text-danger" />
            {:else if fpd.impact === 2}
              <Icon name="emoji-neutral" class="text-warning" />
            {:else if fpd.impact === 1}
              <Icon name="emoji-smile" class="text-success" />
            {:else if fpd.impact === 0}
              <Icon name="emoji-laughing" class="text-info" />
            {:else if fpd.impact === -1}
              <Icon name="emoji-dizzy" class="text-danger" />
            {/if}
          </div>
          <div>
            <!-- Print Values -->
            {fpd.avg} / {fpd.max}
            {fpd.unit} &nbsp; <!-- To increase margin to tooltip: No other way manageable ... -->
          </div>
        </div>
        <Tooltip
          target={`footprint-${job.jobId}-${index}`}
          placement="right"
          offset={[0, 20]}>{fpd.message}</Tooltip
        >
      </div>
      <div class="mb-2">
        <Progress value={fpd.avg} max={fpd.max} color={fpd.color} />
      </div>
    {/each}
    {#if job?.metaData?.message}
      <hr class="mt-1 mb-2" />
      {@html job.metaData.message}
    {/if}
  </CardBody>
</Card>

<style>
  .cursor-help {
    cursor: help;
  }
</style>
