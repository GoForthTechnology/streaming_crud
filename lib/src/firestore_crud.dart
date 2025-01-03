import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:streaming_crud/streaming_crud.dart';

abstract class Indexable<T> {
  String? getId();
  T setId(String id);
}

class FirestoreCrud<T extends Indexable<T>> extends StreamingCrudInterface<T> {
  final String collectionName;
  final T Function(Map<String, dynamic>) fromJson;
  final Map<String, dynamic> Function(T) toJson;

  final _userCompleter = new Completer<User>();
  final FirebaseFirestore _db;

  FirestoreCrud(
      {required this.collectionName,
      required this.fromJson,
      required this.toJson})
      : _db = FirebaseFirestore.instance {
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null && !_userCompleter.isCompleted) {
        var userRef = _db.collection("users").doc(user.uid);
        var userDoc = await userRef.get();
        if (!userDoc.exists) {
          await userRef.set({"active": true});
        }
        _userCompleter.complete(user);
        notifyListeners();
      }
    });
  }

  Future<CollectionReference<T>> _ref() async {
    var user = await _userCompleter.future;
    return _db
        .collection("users")
        .doc(user.uid)
        .collection(collectionName)
        .withConverter<T>(
          fromFirestore: (snapshots, _) => fromJson(snapshots.data()!),
          toFirestore: (value, _) => toJson(value),
        );
  }

  @override
  Stream<T?> get(String id) async* {
    var ref = await _ref();
    yield* ref.doc(id).snapshots().map((s) => s.data()?.setId(s.id));
  }

  @override
  Stream<List<T>> getWhere(List<Criteria> criteria) async* {
    var ref = await _ref();
    Query<T> query = ref;
    for (var c in criteria) {
      query = query.where(c.field,
          isEqualTo: c.isEqualTo,
          isGreaterThan: c.isGreaterThan,
          isLessThan: c.isLessThan,
          isNotEqualTo: c.isNotEqualTo,
          isNull: c.isNull);
    }
    yield* query.snapshots().map((s) => s.docs.map((ds) {
          T t = ds.data().setId(ds.id);
          return t;
        }).toList());
  }

  @override
  Stream<List<T>> getAll() async* {
    var ref = await _ref();
    yield* ref.snapshots().map((s) => s.docs.map((ds) {
          T t = ds.data().setId(ds.id);
          return t;
        }).toList());
  }

  @override
  Future<void> init() async {}

  @override
  Future<String> insert(T t) async {
    var ref = await _ref();
    return ref.add(t).then((ds) => ds.id);
  }

  @override
  Future<void> remove(String id) async {
    var ref = await _ref();
    return ref.doc(id).delete();
  }

  @override
  Future<void> update(T t) async {
    var ref = await _ref();
    return ref.doc(t.getId()).update(toJson(t));
  }
}
