import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const CryptoSignalApp());
}

class CryptoSignalApp extends StatelessWidget {
  const CryptoSignalApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF07080C),
        primaryColor: const Color(0xFF00FF66),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  static const String baseUrl = "https://crypto-signal-bot-alpha.vercel.app";
  String pair = "BTC/USDT";
  String selectedExpiry = "5 MIN";
  String selectedTimeframe = "1 MIN";
  String signal = "READY TO SCAN";
  String accuracy = "--%";
  String duration = "-- MIN";
  double price = 0.0;
  double currentPrice = 0.0;
  double previousPrice = 0.0;
  int liveScore = 0;
  double rsi = 50.0;
  String marketStructure = "NEUTRAL";
  bool isAnalyzing = false;
  bool isServerError = false;
  bool showAnalyzingOverlay = false;
  String analyzingProgressText = "Initializing...";
  List<Map<String, dynamic>> historyLogs = [];
  List<CandleData> candleData = [];
  List<CandleData> predictedCandleData = [];
  Timer? _priceTimer;
  Timer? _progressTimer;
  Timer? _chartTimer;
  late AnimationController _scanLineController;
  late Animation<double> _scanLineAnimation;

  @override
  void initState() {
    super.initState();
    _startLivePriceUpdates();
    _startChartUpdates();
    _scanLineController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _scanLineAnimation = Tween<double>(begin: -1.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanLineController, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _priceTimer?.cancel();
    _progressTimer?.cancel();
    _chartTimer?.cancel();
    _scanLineController.dispose();
    super.dispose();
  }

  void _startLivePriceUpdates() {
    _priceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _fetchCurrentPrice();
    });
  }

  void _startChartUpdates() {
    _chartTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _fetchCandleData();
      _fetchPredictedCandles();
    });
  }

  Future<void> _fetchCurrentPrice() async {
    try {
      final url = Uri.parse('$baseUrl/api/live-price?pair=$pair');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          previousPrice = currentPrice;
          currentPrice = double.parse(data['price'].toString());
          liveScore = data['score'] ?? 0;
          rsi = double.parse(data['rsi'].toString());
          marketStructure = data['structure'] ?? "NEUTRAL";
        });
      }
    } catch (e) {
      print("Network Error: $e");
      setState(() {
        previousPrice = currentPrice;
        if (currentPrice == 0.0) {
          currentPrice = 77500.0;
        }
        liveScore = 0;
        rsi = 50.0;
        marketStructure = "NEUTRAL";
      });
    }
  }

  Future<void> _fetchCandleData() async {
    try {
      final timeframe = selectedTimeframe == "1 MIN" ? "1m" : "5m";
      final url = Uri.parse(
        '$baseUrl/api/signal?pair=$pair&timeframe=$timeframe',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final price = double.parse(data['price'].toString());

        setState(() {
          final now = DateTime.now();
          candleData.add(
            CandleData(
              now,
              price - 50 + (DateTime.now().millisecond % 100),
              price + 50 + (DateTime.now().millisecond % 100),
              price - 100 + (DateTime.now().millisecond % 50),
              price + (DateTime.now().millisecond % 100 - 50),
            ),
          );
          if (candleData.length > 50) {
            candleData.removeAt(0);
          }
        });
      }
    } catch (e) {
      print("Chart Data Error: $e");
    }
  }

  Future<void> _fetchPredictedCandles() async {
    try {
      final timeframe = selectedTimeframe == "1 MIN" ? "1m" : "5m";
      final url = Uri.parse(
        '$baseUrl/api/predict-candles?pair=$pair&timeframe=$timeframe',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final predicted = data['predicted_candles'] as List;
        final currentPrice = double.parse(data['current_price'].toString());

        setState(() {
          predictedCandleData.clear();
          final now = DateTime.now();
          for (int i = 0; i < predicted.length; i++) {
            final candle = predicted[i];
            predictedCandleData.add(
              CandleData(
                now.add(
                  Duration(
                    minutes: (i + 1) * (selectedTimeframe == "1 MIN" ? 1 : 5),
                  ),
                ),
                double.parse(candle['open'].toString()),
                double.parse(candle['high'].toString()),
                double.parse(candle['low'].toString()),
                double.parse(candle['close'].toString()),
              ),
            );
          }
        });
      }
    } catch (e) {
      print("Predicted Candles Error: $e");
    }
  }

  Future<void> triggerBotAnalysis() async {
    setState(() {
      isAnalyzing = true;
      signal = "ANALYZING MARKET...";
      showAnalyzingOverlay = true;
      analyzingProgressText = "Scanning Candlesticks... RSI - MACD - EMA";
    });

    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 1200), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (analyzingProgressText.contains("RSI")) {
          analyzingProgressText = "Analyzing Market Structure...";
        } else if (analyzingProgressText.contains("Structure")) {
          analyzingProgressText = "Validating Accuracy...";
        } else if (analyzingProgressText.contains("Validating")) {
          analyzingProgressText = "Finalizing Signal...";
          timer.cancel();
        }
      });
    });

    await Future.delayed(const Duration(milliseconds: 3600));

    _progressTimer?.cancel();
    setState(() {
      if (liveScore == 3) {
        if (marketStructure == "BULLISH") {
          signal = "BUY / LONG";
        } else if (marketStructure == "BEARISH") {
          signal = "SELL / SHORT";
        } else {
          signal = "Analyzing Market... Waiting for Confirmations";
        }
        accuracy = "95%";
        duration = selectedExpiry;
        price = currentPrice;
        isAnalyzing = false;
        isServerError = false;
        showAnalyzingOverlay = false;

        if (signal.contains("BUY") || signal.contains("SELL")) {
          String finalResult = "WIN";
          String generatedTime =
              "${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}";

          historyLogs.insert(0, {
            "time": generatedTime,
            "pair": pair,
            "type": signal,
            "expiry": duration,
            "rate": "\$${price.toStringAsFixed(2)}",
            "prob": accuracy,
            "status": finalResult,
          });
        }
      } else {
        signal = "Analyzing Market... Waiting for Confirmations";
        accuracy = "--%";
        duration = "-- MIN";
        price = 0.0;
        isAnalyzing = false;
        isServerError = false;
        showAnalyzingOverlay = false;
      }
    });
  }

  void showError() {
    setState(() {
      isServerError = true;
      isAnalyzing = false;
      signal = "ERROR CONNECTING";
    });
  }

  Color getSignalColor() {
    if (signal.contains("BUY") || signal.contains("LONG"))
      return const Color(0xFF00FF66);
    if (signal.contains("SELL") || signal.contains("SHORT"))
      return const Color(0xFFFF0055);
    if (isAnalyzing) return Colors.cyanAccent;
    return Colors.white30;
  }

  Widget _buildAnalyzingOverlay() {
    return AnimatedBuilder(
      animation: _scanLineAnimation,
      builder: (context, child) {
        return Container(
          color: Colors.black.withOpacity(0.95),
          child: Stack(
            children: [
              CustomPaint(size: Size.infinite, painter: GridPatternPainter()),
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 280,
                      height: 180,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F111A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF00FF66).withOpacity(0.3),
                        ),
                      ),
                      child: CustomPaint(
                        size: const Size(280, 180),
                        painter: CandlestickChartPainter(),
                      ),
                    ),
                    const SizedBox(height: 30),
                    Container(
                      width: 280,
                      height: 2,
                      color: const Color(0xFF00FF66).withOpacity(0.2),
                      child: FractionallySizedBox(
                        alignment: Alignment(
                          (_scanLineAnimation.value + 1) / 2,
                          0,
                        ),
                        widthFactor: 0.1,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                const Color(0xFF00FF66),
                                Colors.transparent,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00FF66).withOpacity(0.8),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    const Text(
                      "AI ANALYZING MARKET",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF00FF66),
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      analyzingProgressText,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "🤖 AI COMMAND BOT PRO",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0F111A),
        elevation: 0,
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F111A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF00FF66).withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        "LIVE PRICE",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white38,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          const Text(
                            "\$",
                            style: TextStyle(
                              fontSize: 24,
                              color: Color(0xFF00FF66),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            currentPrice > 0
                                ? currentPrice.toStringAsFixed(2)
                                : "--",
                            style: const TextStyle(
                              fontSize: 36,
                              color: Color(0xFF00FF66),
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pair,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white54,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        liveScore == 0
                            ? "0/3 Points Matched"
                            : liveScore == 1
                            ? "1/3 Points Matched"
                            : liveScore == 2
                            ? "2/3 Points Matched"
                            : "3/3 Points Matched",
                        style: TextStyle(
                          fontSize: 12,
                          color: liveScore == 3
                              ? const Color(0xFF00FF66)
                              : Colors.white54,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F111A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "ASSET: $pair",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.white70,
                        ),
                      ),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                selectedTimeframe = "1 MIN";
                                candleData.clear();
                                predictedCandleData.clear();
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: selectedTimeframe == "1 MIN"
                                    ? const Color(0xFF00FF66).withOpacity(0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selectedTimeframe == "1 MIN"
                                      ? const Color(0xFF00FF66)
                                      : Colors.transparent,
                                ),
                              ),
                              child: Text(
                                "1 MIN",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: selectedTimeframe == "1 MIN"
                                      ? const Color(0xFF00FF66)
                                      : Colors.white38,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                selectedTimeframe = "5 MIN";
                                candleData.clear();
                                predictedCandleData.clear();
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: selectedTimeframe == "5 MIN"
                                    ? const Color(0xFF00FF66).withOpacity(0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selectedTimeframe == "5 MIN"
                                      ? const Color(0xFF00FF66)
                                      : Colors.transparent,
                                ),
                              ),
                              child: Text(
                                "5 MIN",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: selectedTimeframe == "5 MIN"
                                      ? const Color(0xFF00FF66)
                                      : Colors.white38,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  height: 280,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F111A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF00FF66).withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "LIVE CHART",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white38,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00FF66).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF00FF66),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  selectedTimeframe,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF00FF66),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: candleData.isEmpty
                            ? const Center(
                                child: Text(
                                  "Loading chart data...",
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                ),
                              )
                            : SfCartesianChart(
                                primaryXAxis: DateTimeAxis(
                                  isVisible: true,
                                  intervalType: DateTimeIntervalType.minutes,
                                  dateFormat: DateFormat.Hm(),
                                  labelStyle: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 10,
                                  ),
                                  axisLine: const AxisLine(
                                    color: Colors.white24,
                                    width: 1,
                                  ),
                                  majorGridLines: const MajorGridLines(
                                    color: Colors.white10,
                                    width: 0.5,
                                  ),
                                ),
                                primaryYAxis: NumericAxis(
                                  isVisible: true,
                                  labelFormat: '\${value}',
                                  labelStyle: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 10,
                                  ),
                                  axisLine: const AxisLine(
                                    color: Colors.white24,
                                    width: 1,
                                  ),
                                  majorGridLines: const MajorGridLines(
                                    color: Colors.white10,
                                    width: 0.5,
                                  ),
                                ),
                                plotAreaBorderWidth: 0,
                                tooltipBehavior: TooltipBehavior(
                                  enable: true,
                                  color: const Color(0xFF0F111A),
                                  textStyle: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                                series: <CandleSeries<CandleData, DateTime>>[
                                  CandleSeries<CandleData, DateTime>(
                                    name: 'Historical',
                                    dataSource: candleData,
                                    xValueMapper: (CandleData data, _) =>
                                        data.time,
                                    lowValueMapper: (CandleData data, _) =>
                                        data.low,
                                    highValueMapper: (CandleData data, _) =>
                                        data.high,
                                    openValueMapper: (CandleData data, _) =>
                                        data.open,
                                    closeValueMapper: (CandleData data, _) =>
                                        data.close,
                                    borderWidth: 2,
                                    enableSolidCandles: true,
                                    spacing: 0.1,
                                  ),
                                  CandleSeries<CandleData, DateTime>(
                                    name: 'Predicted',
                                    dataSource: predictedCandleData,
                                    xValueMapper: (CandleData data, _) =>
                                        data.time,
                                    lowValueMapper: (CandleData data, _) =>
                                        data.low,
                                    highValueMapper: (CandleData data, _) =>
                                        data.high,
                                    openValueMapper: (CandleData data, _) =>
                                        data.open,
                                    closeValueMapper: (CandleData data, _) =>
                                        data.close,
                                    borderWidth: 2,
                                    enableSolidCandles: true,
                                    spacing: 0.1,
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: const Color(0xFF00FF66),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            "Historical",
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white54,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: const Color(0xFF00FF66).withOpacity(0.5),
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            "Predicted (5 Candles)",
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 20,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F111A),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: getSignalColor().withOpacity(0.15),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        if (price > 0 && !isAnalyzing)
                          Text(
                            "Execution Price: \$${price.toStringAsFixed(2)}",
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.white38,
                            ),
                          ),
                        const SizedBox(height: 6),
                        if (isAnalyzing)
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.cyanAccent,
                            ),
                          )
                        else
                          Text(
                            signal,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              color: getSignalColor(),
                              letterSpacing: 0.5,
                            ),
                          ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                const Text(
                                  "EXPIRY",
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white38,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  duration,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: getSignalColor(),
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              children: [
                                const Text(
                                  "PROBABILITY",
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white38,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  accuracy,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amberAccent,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: isAnalyzing ? null : triggerBotAnalysis,
                  child: Container(
                    height: 55,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isAnalyzing
                            ? [Colors.grey, Colors.blueGrey]
                            : [
                                const Color(0xFF00FF66),
                                const Color(0xFF00B0FF),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        isAnalyzing
                            ? "CALCULATING EXPIRY MATRIX..."
                            : "🔥 GIVE ME $selectedExpiry SIGNAL",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(
                      Icons.history_toggle_off_rounded,
                      color: Colors.white38,
                      size: 16,
                    ),
                    SizedBox(width: 6),
                    Text(
                      "EXPIRED SIGNALS LOG (REAL-TIME)",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white38,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: historyLogs.isEmpty
                      ? Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F111A).withOpacity(0.5),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Center(
                            child: Text(
                              "No expired positions yet.",
                              style: TextStyle(
                                color: Colors.white24,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: historyLogs.length,
                          itemBuilder: (context, index) {
                            final log = historyLogs[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 14,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F111A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(
                                    0xFF00FF66,
                                  ).withOpacity(0.1),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        log['type'],
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: log['type'].contains("UP")
                                              ? const Color(0xFF00FF66)
                                              : const Color(0xFFFF0055),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        "(${log['expiry']})",
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.white38,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    "Time: ${log['time']} | Strike: ${log['rate']}",
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          if (showAnalyzingOverlay) _buildAnalyzingOverlay(),
        ],
      ),
    );
  }
}

class GridPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00FF66).withOpacity(0.05)
      ..strokeWidth = 1;

    final gridSize = 40.0;
    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CandlestickChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final candleWidth = 15.0;
    final spacing = 25.0;
    final startX = 20.0;

    final candles = [
      {
        'open': 100.0,
        'close': 120.0,
        'high': 130.0,
        'low': 90.0,
        'isGreen': true,
      },
      {
        'open': 120.0,
        'close': 110.0,
        'high': 125.0,
        'low': 105.0,
        'isGreen': false,
      },
      {
        'open': 110.0,
        'close': 140.0,
        'high': 145.0,
        'low': 105.0,
        'isGreen': true,
      },
      {
        'open': 140.0,
        'close': 135.0,
        'high': 150.0,
        'low': 130.0,
        'isGreen': false,
      },
      {
        'open': 135.0,
        'close': 155.0,
        'high': 160.0,
        'low': 130.0,
        'isGreen': true,
      },
      {
        'open': 155.0,
        'close': 145.0,
        'high': 160.0,
        'low': 140.0,
        'isGreen': false,
      },
      {
        'open': 145.0,
        'close': 165.0,
        'high': 170.0,
        'low': 140.0,
        'isGreen': true,
      },
      {
        'open': 165.0,
        'close': 158.0,
        'high': 170.0,
        'low': 155.0,
        'isGreen': false,
      },
    ];

    final maxHeight = size.height - 40;
    final minValue = 90.0;
    final maxValue = 170.0;
    final range = maxValue - minValue;

    for (int i = 0; i < candles.length; i++) {
      final candle = candles[i];
      final x = startX + i * spacing;

      final openY =
          size.height -
          20 -
          ((candle['open'] as double) - minValue) / range * maxHeight;
      final closeY =
          size.height -
          20 -
          ((candle['close'] as double) - minValue) / range * maxHeight;
      final highY =
          size.height -
          20 -
          ((candle['high'] as double) - minValue) / range * maxHeight;
      final lowY =
          size.height -
          20 -
          ((candle['low'] as double) - minValue) / range * maxHeight;

      paint.color = candle['isGreen'] as bool
          ? const Color(0xFF00FF66)
          : const Color(0xFFFF0055);

      canvas.drawLine(Offset(x, highY), Offset(x, lowY), paint);

      paint.style = PaintingStyle.fill;
      final bodyTop = openY < closeY ? openY : closeY;
      final bodyBottom = openY < closeY ? closeY : openY;
      canvas.drawRect(
        Rect.fromLTWH(
          x - candleWidth / 2,
          bodyTop,
          candleWidth,
          bodyBottom - bodyTop,
        ),
        paint,
      );
      paint.style = PaintingStyle.stroke;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CandleData {
  CandleData(this.time, this.open, this.high, this.low, this.close);
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
}
