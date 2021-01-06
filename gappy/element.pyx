"""
GAP element wrapper

This document describes the individual wrappers for various GAP
elements. For general information about GAP, you should read the
:mod:`~sage.libs.gap.libgap` module documentation.
"""

# ****************************************************************************
#       Copyright (C) 2012 Volker Braun <vbraun.name@gmail.com>
#       Copyright (C) 2021 E. Madison Bray <embray@lri.fr>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#                  https://www.gnu.org/licenses/
# ****************************************************************************

from cpython.object cimport Py_EQ, Py_NE, Py_LE, Py_GE, Py_LT, Py_GT
from cysignals.signals cimport sig_on, sig_off

from .gap_includes cimport *
from .core cimport *
from .exceptions import GAPError

#from sage.cpython.string cimport str_to_bytes, char_to_str
cdef str_to_bytes(str s, str encoding='utf-8', str errors='strict'):
    return s.encode(encoding, errors)
cdef char_to_str(char *s):
    return s.decode('utf-8')
#from sage.misc.cachefunc import cached_method
def cached_method(func):
    return func
#from sage.rings.all import ZZ, QQ, RDF
ZZ = object()
QQ = object()
RDF = object()

#from sage.groups.perm_gps.permgroup_element cimport PermutationGroupElement
cdef class PermutationGroupElement:
    pass
#from sage.combinat.permutation import Permutation
cdef class Permutation:
    pass
#from sage.structure.coerce cimport coercion_model as cm
cdef class cm:
    def common_parent(self, *args, **kwargs):
        pass

decode_type_number = {
    0: 'T_INT (integer)',
    T_INTPOS: 'T_INTPOS (positive integer)',
    T_INTNEG: 'T_INTNEG (negative integer)',
    T_RAT: 'T_RAT (rational number)',
    T_CYC: 'T_CYC (universal cyclotomic)',
    T_FFE: 'T_FFE (finite field element)',
    T_PERM2: 'T_PERM2',
    T_PERM4: 'T_PERM4',
    T_BOOL: 'T_BOOL',
    T_CHAR: 'T_CHAR',
    T_FUNCTION: 'T_FUNCTION',
    T_PLIST: 'T_PLIST',
    T_PLIST_CYC: 'T_PLIST_CYC',
    T_BLIST: 'T_BLIST',
    T_STRING: 'T_STRING',
    T_MACFLOAT: 'T_MACFLOAT (hardware floating point number)',
    T_COMOBJ: 'T_COMOBJ (component object)',
    T_POSOBJ: 'T_POSOBJ (positional object)',
    T_DATOBJ: 'T_DATOBJ (data object)',
    T_WPOBJ:  'T_WPOBJ (weak pointer object)',
    }

############################################################################
### helper functions to construct lists and records ########################
############################################################################

cdef Obj make_gap_list(parent, sage_list) except NULL:
    """
    Convert Sage lists into Gap lists

    INPUT:

    - ``a`` -- list of :class:`GapObj`.

    OUTPUT:

    The list of the elements in ``a`` as a Gap ``Obj``.
    """
    cdef GapObj l = parent.eval('[]')
    cdef GapObj elem
    for x in sage_list:
        if not isinstance(x, GapObj):
            elem = <GapObj>parent(x)
        else:
            elem = <GapObj>x

        AddList(l.value, elem.value)
    return l.value


cdef Obj make_gap_matrix(parent, sage_list, gap_ring) except NULL:
    """
    Convert Sage lists into Gap matrices

    INPUT:

    - ``sage_list`` -- list of :class:`GapObj`.

    - ``gap_ring`` -- the base ring

    If ``gap_ring`` is ``None``, nothing is made to make sure
    that all coefficients live in the same Gap ring. The resulting Gap list
    may not be recognized as a matrix by Gap.

    OUTPUT:

    The list of the elements in ``sage_list`` as a Gap ``Obj``.
    """
    cdef GapObj l = parent.eval('[]')
    cdef GapObj elem
    cdef GapObj one
    if gap_ring is not None:
        one = <GapObj>gap_ring.One()
    else:
        one = <GapObj>parent(1)
    for x in sage_list:
        if not isinstance(x, GapObj):
            elem = <GapObj>parent(x)
            elem = elem * one
        else:
            elem = <GapObj>x

        AddList(l.value, elem.value)
    return l.value


cdef char *capture_stdout(Obj func, Obj obj):
    """
    Call a single-argument GAP function ``func`` with the argument ``obj``
    and return the stdout from that function call.

    This can be used to capture the output of GAP functions that are used to
    print objects such as ``Print()`` and ``ViewObj()``.
    """
    cdef Obj s, stream, output_text_string
    cdef UInt res
    # The only way to get a string representation of an object that is truly
    # consistent with how it would be represented at the GAP REPL is to call
    # ViewObj on it.  Unfortunately, ViewObj *prints* to the output stream,
    # and there is no equivalent that simply returns the string that would be
    # printed.  The closest approximation would be DisplayString, but this
    # bypasses any type-specific overrides for ViewObj so for many objects
    # that does not give consistent results.
    # TODO: This is probably needlessly slow, but we might need better
    # support from GAP to improve this...
    try:
        GAP_Enter()
        s = NEW_STRING(0)
        output_text_string = GAP_ValueGlobalVariable("OutputTextString")
        stream = CALL_2ARGS(output_text_string, s, GAP_True)

        if not OpenOutputStream(stream):
            raise GAPError("failed to open output capture stream for "
                           "representing GAP object")

        CALL_1ARGS(func, obj)
        CloseOutput()
        return CSTR_STRING(s)
    finally:
        GAP_Leave()


cdef char *gap_element_repr(Obj obj):
    """
    Implement ``repr()`` of ``GapObj``s using the ``ViewObj()`` function,
    which is by default closest to what you get when displaying an object in
    GAP on the command-line (i.e. when evaluating an expression that returns
    that object.
    """

    cdef Obj func = GAP_ValueGlobalVariable("ViewObj")
    return capture_stdout(func, obj)


cdef char *gap_element_str(Obj obj):
    """
    Implement ``str()`` of ``GapObj``s using the ``Print()`` function.

    This mirrors somewhat how Python uses ``str()`` on an object when passing
    it to the ``print()`` function.  This is also how the GAP pexpect interface
    has traditionally repr'd objects; for the libgap interface we take a
    slightly different approach more closely mirroring Python's str/repr
    difference (though this does not map perfectly onto GAP).
    """
    cdef Obj func = GAP_ValueGlobalVariable("Print")
    return capture_stdout(func, obj)


cdef Obj make_gap_record(parent, sage_dict) except NULL:
    """
    Convert Sage lists into Gap lists

    INPUT:

    - ``a`` -- list of :class:`GapObj`.

    OUTPUT:

    The list of the elements in ``a`` as a Gap ``Obj``.

    TESTS::

        >>> gap({'a': 1, 'b':123})   # indirect doctest
        rec( a := 1, b := 123 )
    """
    data = [ (str(key), parent(value)) for key, value in sage_dict.iteritems() ]

    cdef Obj rec
    cdef GapObj val
    cdef UInt rnam

    try:
        GAP_Enter()
        rec = NEW_PREC(len(data))
        for d in data:
            key, val = d
            rnam = RNamName(str_to_bytes(key))
            AssPRec(rec, rnam, val.value)
        return rec
    finally:
        GAP_Leave()


cdef Obj make_gap_integer(sage_int) except NULL:
    """
    Convert Sage integer into Gap integer

    INPUT:

    - ``sage_int`` -- a Sage integer.

    OUTPUT:

    The integer as a GAP ``Obj``.

    TESTS::

        >>> gap(1)   # indirect doctest
        1
    """
    cdef Obj result
    try:
        GAP_Enter()
        result = INTOBJ_INT(<int>sage_int)
        return result
    finally:
        GAP_Leave()


cdef Obj make_gap_string(sage_string) except NULL:
    """
    Convert a Python string to a Gap string

    INPUT:

    - ``sage_string`` -- a Python str.

    OUTPUT:

    The string as a GAP ``Obj``.

    TESTS::

        >>> gap('string')   # indirect doctest
        "string"
    """
    cdef Obj result
    try:
        GAP_Enter()
        b = str_to_bytes(sage_string)
        C_NEW_STRING(result, len(b), b)
        return result
    finally:
        GAP_Leave()


############################################################################
### generic construction of GapObjs ########################################
############################################################################

cdef GapObj make_any_gap_element(parent, Obj obj):
    """
    Return the GAP element wrapper of ``obj``

    The most suitable subclass of GapObj is determined
    automatically. Use this function to wrap GAP objects unless you
    know exactly which type it is (then you can use the specialized
    ``make_GapElement_...``)

    TESTS::

        >>> T_CHAR = gap.eval("'c'");  T_CHAR
        "c"
        >>> type(T_CHAR)
        <type 'sage.libs.gap.element.GapString'>

        >>> gap.eval("['a', 'b', 'c']")   # gap strings are also lists of chars
        "abc"
        >>> t = gap.UnorderedTuples('abc', 2);  t
        [ "aa", "ab", "ac", "bb", "bc", "cc" ]
        >>> t[1]
        "ab"
        >>> t[1].sage()
        'ab'
        >>> t.sage()
        ['aa', 'ab', 'ac', 'bb', 'bc', 'cc']

    Check that :trac:`18158` is fixed::

        >>> S = SymmetricGroup(5)
        >>> irr = gap.Irr(S)[3]
        >>> irr[0]
        6
        >>> irr[1]
        0
    """
    cdef int num

    try:
        GAP_Enter()
        if obj is NULL:
            return make_GapObj(parent, obj)
        num = TNUM_OBJ(obj)
        if IS_INT(obj):
            return make_GapInteger(parent, obj)
        elif num == T_MACFLOAT:
            return make_GapFloat(parent, obj)
        elif num == T_CYC:
            return make_GapCyclotomic(parent, obj)
        elif num == T_FFE:
            return make_GapFiniteField(parent, obj)
        elif num == T_RAT:
            return make_GapRational(parent, obj)
        elif num == T_BOOL:
            return make_GapBoolean(parent, obj)
        elif num == T_FUNCTION:
            return make_GapFunction(parent, obj)
        elif num == T_PERM2 or num == T_PERM4:
            return make_GapPermutation(parent, obj)
        elif IS_REC(obj):
            return make_GapRecord(parent, obj)
        elif IS_LIST(obj) and LEN_LIST(obj) == 0:
            # Empty lists are lists and not strings in Python
            return make_GapList(parent, obj)
        elif IsStringConv(obj):
            # GAP strings are lists, too. Make sure this comes before non-empty make_GapList
            return make_GapString(parent, obj)
        elif IS_LIST(obj):
            return make_GapList(parent, obj)
        elif num == T_CHAR:
            ch = make_GapObj(parent, obj).IntChar().sage()
            return make_GapString(parent, make_gap_string(chr(ch)))
        result = make_GapObj(parent, obj)
        if num == T_POSOBJ:
            if result.IsZmodnZObj():
                return make_GapIntegerMod(parent, obj)
        if num == T_COMOBJ:
            if result.IsRing():
                return make_GapRing(parent, obj)
        return result
    finally:
        GAP_Leave()


############################################################################
### GapObj #################################################################
############################################################################

cdef GapObj make_GapObj(parent, Obj obj):
    r"""
    Turn a Gap C object (of type ``Obj``) into a Cython ``GapObj``.

    INPUT:

    - ``parent`` -- the parent of the new :class:`GapObj`

    - ``obj`` -- a GAP object.

    OUTPUT:

    A :class:`GapFunction` instance, or one of its derived
    classes if it is a better fit for the GAP object.

    EXAMPLES::

        >>> gap(0)
        0
        >>> type(_)
        <type 'sage.libs.gap.element.GapInteger'>

        >>> gap.eval('')
        >>> gap(None)
        Traceback (most recent call last):
        ...
        AttributeError: 'NoneType' object has no attribute '_libgap_init_'
    """
    cdef GapObj r = GapObj.__new__(GapObj)
    r._initialize(parent, obj)
    return r


cpdef _from_sage(gap, elem):
    """
    Currently just used for unpickling; equivalent to calling ``gap(elem)``
    to convert a Sage object to a `GapObj` where possible.
    """
    if isinstance(elem, str):
        return gap.eval(elem)

    return gap(elem)


cdef class GapObj:
    r"""
    Wrapper for all Gap objects.

    .. NOTE::

        In order to create ``GapObjs`` you should use the ``gap`` instance (the
        parent of all Gap elements) to convert things into ``GapObj``. You must
        not create ``GapObj`` instances manually.

    EXAMPLES::

        >>> gap(0)
        0

    If Gap finds an error while evaluating, a :class:`GAPError`
    exception is raised::

        >>> gap.eval('1/0')
        Traceback (most recent call last):
        ...
        GAPError: Error, Rational operations: <divisor> must not be zero

    Also, a ``GAPError`` is raised if the input is not a simple expression::

        >>> gap.eval('1; 2; 3')
        Traceback (most recent call last):
        ...
        GAPError: can only evaluate a single statement
    """

    def __cinit__(self):
        """
        The Cython constructor.

        EXAMPLES::

            >>> gap.eval('1')
            1
        """
        self.value = NULL
        self._compare_by_id = False

    def __init__(self):
        """
        The ``GapObj`` constructor

        Users must use the ``gap`` instance to construct instances of
        :class:`GapObj`. Cython programmers must use :func:`make_GapObj`
        factory function.

        TESTS::

            >>> from sage.libs.gap.element import GapElement
            >>> GapObj()
            Traceback (most recent call last):
            ...
            TypeError: this class cannot be instantiated from Python
        """
        raise TypeError('this class cannot be instantiated from Python')

    cdef _initialize(self, parent, Obj obj):
        r"""
        Initialize the GapObj.

        This Cython method is called from :func:`make_GapObj` to
        initialize the newly-constructed object. You must never call
        it manually.

        TESTS::

            >>> n_before = gap.count_GAP_objects()
            >>> a = gap.eval('123')
            >>> b = gap.eval('456')
            >>> c = gap.eval('CyclicGroup(3)')
            >>> d = gap.eval('"a string"')
            >>> gap.collect()
            >>> del c
            >>> gap.collect()
            >>> n_after = gap.count_GAP_objects()
            >>> n_after - n_before
            3
        """
        assert self.value is NULL
        self._parent = parent
        self.value = obj
        if obj is NULL:
            return
        reference_obj(obj)

    def __dealloc__(self):
        r"""
        The Cython destructor

        TESTS::

            >>> pre_refcount = gap.count_GAP_objects()
            >>> def f():
            ...     local_variable = gap.eval('"This is a new string"')
            >>> f()
            >>> f()
            >>> f()
            >>> post_refcount = gap.count_GAP_objects()
            >>> post_refcount - pre_refcount
            0
        """
        if self.value is NULL:
            return
        dereference_obj(self.value)

    def __copy__(self):
        r"""
        TESTS::

            >>> a = gap(1)
            >>> a.__copy__() is a
            True

            >>> a = gap(1/3)
            >>> a.__copy__() is a
            True

            >>> a = gap([1,2])
            >>> b = a.__copy__()
            >>> a is b
            False
            >>> a[0] = 3
            >>> a
            [ 3, 2 ]
            >>> b
            [ 1, 2 ]

            >>> a = gap([[0,1],[2,3,4]])
            >>> b = a.__copy__()
            >>> b[0][1] = -2
            >>> b
            [ [ 0, -2 ], [ 2, 3, 4 ] ]
            >>> a
            [ [ 0, -2 ], [ 2, 3, 4 ] ]
        """
        if IS_MUTABLE_OBJ(self.value):
            return make_any_gap_element(self.parent(), SHALLOW_COPY_OBJ(self.value))
        else:
            return self

    def parent(self, x=None):
        """
        For backwards-compatibility with Sage, returns either the
        `~gappy.core.Gap` interpreter instance associated with this `GapObj`,
        or the result of coercing ``x`` to a `GapObj`.
        """

        if x is None:
            return self._parent
        else:
            return self._parent(x)

    cpdef GapObj deepcopy(self, bint mut):
        r"""
        Return a deepcopy of this Gap object

        Note that this is the same thing as calling ``StructuralCopy`` but much
        faster.

        INPUT:

        - ``mut`` - (boolean) wheter to return an mutable copy

        EXAMPLES::

            >>> a = gap([[0,1],[2,3]])
            >>> b = a.deepcopy(1)
            >>> b[0,0] = 5
            >>> a
            [ [ 0, 1 ], [ 2, 3 ] ]
            >>> b
            [ [ 5, 1 ], [ 2, 3 ] ]

            >>> l = gap([0,1])
            >>> l.deepcopy(0).IsMutable()
            false
            >>> l.deepcopy(1).IsMutable()
            true
        """
        if IS_MUTABLE_OBJ(self.value):
            return make_any_gap_element(self.parent(), CopyObj(self.value, mut))
        else:
            return self

    def __deepcopy__(self, memo):
        r"""
        TESTS::

            >>> a = gap([[0,1],[2]])
            >>> b = deepcopy(a)
            >>> a[0,0] = -1
            >>> a
            [ [ -1, 1 ], [ 2 ] ]
            >>> b
            [ [ 0, 1 ], [ 2 ] ]
        """
        return self.deepcopy(0)

    def __reduce__(self):
        """
        Attempt to pickle GAP elements from libgap.

        This is inspired in part by
        ``sage.interfaces.interface.Interface._reduce``, though for a fallback
        we use ``str(self)`` instead of ``repr(self)``, since the former is
        equivalent in the libgap interface to the latter in the pexpect
        interface.

        TESTS:

        This workaround was motivated in particular by this example from the
        permutation groups implementation::

            >>> CC = gap.eval('ConjugacyClass(SymmetricGroup([ 1 .. 5 ]), (1,2)(3,4))')
            >>> CC.sage()
            Traceback (most recent call last):
            ...
            NotImplementedError: cannot construct equivalent Sage object
            >>> gap.eval(str(CC))
            (1,2)(3,4)^G
            >>> loads(dumps(CC))
            (1,2)(3,4)^G
        """

        if self.is_string():
            elem = repr(self.sage())
        try:
            elem = self.sage()
        except NotImplementedError:
            elem = str(self)

        # TODO: This might be broken, since I'm not sure the Gap instance
        # itself can be successfully pickled.  Will come back to this later.
        return (_from_sage, (self.parent(), elem))

    def __contains__(self, other):
        r"""
        TESTS::

            >>> gap(1) in gap.eval('Integers')
            True
            >>> 1 in gap.eval('Integers')
            True

            >>> 3 in gap([1,5,3,2])
            True
            >>> -5 in gap([1,5,3,2])
            False

            >>> gap.eval('Integers') in gap(1)
            Traceback (most recent call last):
            ...
            GAPError: Error, no method found! Error, no 1st choice method found for `in' on 2 arguments
        """
        GAP_IN = self.parent().eval(r'\in')
        return GAP_IN(other, self).sage()

    cpdef _type_number(self):
        """
        Return the GAP internal type number.

        This is only useful for libgap development purposes.

        OUTPUT:

        Integer.

        EXAMPLES::

            >>> x = gap(1)
            >>> x._type_number()
            (0, 'T_INT (integer)')
        """
        n = TNUM_OBJ(self.value)
        global decode_type_number
        name = decode_type_number.get(n, 'unknown')
        return (n, name)

    def __dir__(self):
        """
        Customize tab completion

        EXAMPLES::

            >>> G = gap.DihedralGroup(4)
            >>> 'GeneratorsOfMagmaWithInverses' in dir(G)
            True
            >>> 'GeneratorsOfGroup' in dir(G)    # known bug
            False
            >>> x = gap(1)
            >>> len(dir(x)) > 100
            True
        """
        from sage.libs.gap.operations import OperationInspector
        ops = OperationInspector(self).op_names()
        return dir(self.__class__) + ops

    def __getattr__(self, name):
        r"""
        Return functionoid implementing the function ``name``.

        EXAMPLES::

            >>> lst = gap([])
            >>> 'Add' in dir(lst)    # This is why tab-completion works
            True
            >>> lst.Add(1)    # this is the syntactic sugar
            >>> lst
            [ 1 ]

        The above is equivalent to the following calls::

            >>> lst = gap.eval('[]')
            >>> gap.eval('Add') (lst, 1)
            >>> lst
            [ 1 ]

        TESTS::

            >>> lst.Adddddd(1)
            Traceback (most recent call last):
            ...
            AttributeError: 'Adddddd' is not defined in GAP

            >>> gap.eval('some_name := 1')
            1
            >>> lst.some_name
            Traceback (most recent call last):
            ...
            AttributeError: 'some_name' does not define a GAP function
        """
        if name in ('__dict__', '_getAttributeNames', '__custom_name', 'keys'):
            raise AttributeError('Python special name, not a GAP function.')
        try:
            proxy = make_GapMethodProxy(self.parent(), gap_eval(name), self)
        except GAPError:
            raise AttributeError(f"'{name}' is not defined in GAP")
        if not proxy.is_function():
            raise AttributeError(f"'{name}' does not define a GAP function")
        return proxy

    def __str__(self):
        r"""
        Return a string representation of ``self`` for printing.

        EXAMPLES::

            >>> gap(0)
            0
            >>> print(gap.eval(''))
            None
            >>> print(gap('a'))
            a
            >>> print(gap.eval('SymmetricGroup(3)'))
            SymmetricGroup( [ 1 .. 3 ] )
            >>> gap(0).__str__()
            '0'
        """
        if  self.value == NULL:
            return 'NULL'

        s = char_to_str(gap_element_str(self.value))
        return s.strip()

    def _repr_(self):
        r"""
        Return a string representation of ``self``.

        EXAMPLES::

            >>> gap(0)
            0
            >>> gap.eval('')
            >>> gap('a')
            "a"
            >>> gap.eval('SymmetricGroup(3)')
            Sym( [ 1 .. 3 ] )
            >>> gap(0)._repr_()
            '0'
        """
        if  self.value == NULL:
            return 'NULL'

        s = char_to_str(gap_element_repr(self.value))
        return s.strip()

    cpdef _set_compare_by_id(self):
        """
        Set comparison to compare by ``id``

        By default, GAP is used to compare GAP objects. However,
        this is not defined for all GAP objects. To have GAP play
        nice with ``UniqueRepresentation``, comparison must always
        work. This method allows one to override the comparison to
        sort by the (unique) Python ``id``.

        Obviously it is a bad idea to change the comparison of objects
        after you have inserted them into a set/dict. You also must
        not mix GAP objects with different sort methods in the same
        container.

        EXAMPLES::

            >>> F1 = gap.FreeGroup(['a'])
            >>> F2 = gap.FreeGroup(['a'])
            >>> F1 < F2
            Traceback (most recent call last):
            ...
            GAPError: Error, no method found!
            Error, no 1st choice method found for `<' on 2 arguments

            >>> F1._set_compare_by_id()
            >>> F1 != F2
            Traceback (most recent call last):
            ...
            ValueError: comparison style must be the same for both operands

            >>> F1._set_compare_by_id()
            >>> F2._set_compare_by_id()
            >>> F1 != F2
            True
        """
        self._compare_by_id = True

    cpdef _assert_compare_by_id(self):
        """
        Ensure that comparison is by ``id``

        See :meth:`_set_compare_by_id`.

        OUTPUT:

        This method returns nothing. A ``ValueError`` is raised if
        :meth:`_set_compare_by_id` has not been called on this libgap
        object.

        EXAMPLES::

            >>> x = gap.FreeGroup(1)
            >>> x._assert_compare_by_id()
            Traceback (most recent call last):
            ...
            ValueError: this requires a GAP object whose comparison is by "id"

            >>> x._set_compare_by_id()
            >>> x._assert_compare_by_id()
        """
        if not self._compare_by_id:
            raise ValueError('this requires a GAP object whose comparison is by "id"')

    def __hash__(self):
        """
        Make hashable.

        EXAMPLES::

            >>> hash(gap(123))   # random output
            163512108404620371
        """
        return hash(str(self))

    cpdef _richcmp_(self, other, int op):
        """
        Compare ``self`` with ``other``.

        Uses the GAP comparison by default, or the Python ``id`` if
        :meth:`_set_compare_by_id` was called.

        OUTPUT:

        Boolean, depending on the comparison of ``self`` and
        ``other``.  Raises a ``ValueError`` if GAP does not support
        comparison of ``self`` and ``other``, unless
        :meth:`_set_compare_by_id` was called on both ``self`` and
        ``other``.

        EXAMPLES::

            >>> a = gap(123)
            >>> a == a
            True
            >>> b = gap('string')
            >>> a._richcmp_(b, 0)
            1
            >>> (a < b) or (a > b)
            True
            >>> a._richcmp_(gap(123), 2)
            True

        GAP does not have a comparison function for two ``FreeGroup``
        objects. LibGAP signals this by raising a ``ValueError`` ::

            >>> F1 = gap.FreeGroup(['a'])
            >>> F2 = gap.FreeGroup(['a'])
            >>> F1 < F2
            Traceback (most recent call last):
            ...
            GAPError: Error, no method found!
            Error, no 1st choice method found for `<' on 2 arguments

            >>> F1._set_compare_by_id()
            >>> F1 < F2
            Traceback (most recent call last):
            ...
            ValueError: comparison style must be the same for both operands

            >>> F1._set_compare_by_id()
            >>> F2._set_compare_by_id()
            >>> F1 < F2 or F1 > F2
            True

        Check that :trac:`26388` is fixed::

            >>> 1 > gap(1)
            False
            >>> gap(1) > 1
            False
            >>> 1 >= gap(1)
            True
            >>> gap(1) >= 1
            True
        """
        if self._compare_by_id != (<GapObj>other)._compare_by_id:
            raise ValueError("comparison style must be the same for both operands")
        if op==Py_LT:
            return self._compare_less(other)
        elif op==Py_LE:
            return self._compare_equal(other) or self._compare_less(other)
        elif op == Py_EQ:
            return self._compare_equal(other)
        elif op == Py_GT:
            return not self._compare_less(other) and not self._compare_equal(other)
        elif op == Py_GE:
            return not self._compare_less(other)
        elif op == Py_NE:
            return not self._compare_equal(other)
        else:
            assert False  # unreachable

    cdef bint _compare_equal(self, Element other) except -2:
        """
        Compare ``self`` with ``other``.

        Helper for :meth:`_richcmp_`

        EXAMPLES::

            >>> gap(1) == gap(1)   # indirect doctest
            True
        """
        if self._compare_by_id:
            return id(self) == id(other)
        cdef GapObj c_other = <GapObj>other
        sig_on()
        try:
            GAP_Enter()
            return EQ(self.value, c_other.value)
        finally:
            GAP_Leave()
            sig_off()

    cdef bint _compare_less(self, Element other) except -2:
        """
        Compare ``self`` with ``other``.

        Helper for :meth:`_richcmp_`

        EXAMPLES::

            >>> gap(1) < gap(2)   # indirect doctest
            True
        """
        if self._compare_by_id:
            return id(self) < id(other)
        cdef GapObj c_other = <GapObj>other
        sig_on()
        try:
            GAP_Enter()
            return LT(self.value, c_other.value)
        finally:
            GAP_Leave()
            sig_off()

    cpdef _add_(self, right):
        r"""
        Add two GapObj objects.

        EXAMPLES::

            >>> g1 = gap(1)
            >>> g2 = gap(2)
            >>> g1._add_(g2)
            3
            >>> g1 + g2    # indirect doctest
            3

            >>> gap(1) + gap.CyclicGroup(2)
            Traceback (most recent call last):
            ...
            GAPError: Error, no method found!
            Error, no 1st choice method found for `+' on 2 arguments
        """
        cdef Obj result
        try:
            sig_GAP_Enter()
            sig_on()
            result = SUM(self.value, (<GapObj>right).value)
            sig_off()
        finally:
            GAP_Leave()
        return make_any_gap_element(self.parent(), result)

    cpdef _sub_(self, right):
        r"""
        Subtract two GapObj objects.

        EXAMPLES::

            >>> g1 = gap(1)
            >>> g2 = gap(2)
            >>> g1._sub_(g2)
            -1
            >>> g1 - g2    # indirect doctest
            -1

            >>> gap(1) - gap.CyclicGroup(2)
            Traceback (most recent call last):
            ...
            GAPError: Error, no method found! ...
        """
        cdef Obj result
        try:
            sig_GAP_Enter()
            sig_on()
            result = DIFF(self.value, (<GapObj>right).value)
            sig_off()
        finally:
            GAP_Leave()
        return make_any_gap_element(self.parent(), result)


    cpdef _mul_(self, right):
        r"""
        Multiply two GapObj objects.

        EXAMPLES::

            >>> g1 = gap(3)
            >>> g2 = gap(5)
            >>> g1._mul_(g2)
            15
            >>> g1 * g2    # indirect doctest
            15

            >>> gap(1) * gap.CyclicGroup(2)
            Traceback (most recent call last):
            ...
            GAPError: Error, no method found!
            Error, no 1st choice method found for `*' on 2 arguments
        """
        cdef Obj result
        try:
            sig_GAP_Enter()
            sig_on()
            result = PROD(self.value, (<GapObj>right).value)
            sig_off()
        finally:
            GAP_Leave()
        return make_any_gap_element(self.parent(), result)

    cpdef _div_(self, right):
        r"""
        Divide two GapObj objects.

        EXAMPLES::

            >>> g1 = gap(3)
            >>> g2 = gap(5)
            >>> g1._div_(g2)
            3/5
            >>> g1 / g2    # indirect doctest
            3/5

            >>> gap(1) / gap.CyclicGroup(2)
            Traceback (most recent call last):
            ...
            GAPError: Error, no method found!
            Error, no 1st choice method found for `/' on 2 arguments

            >>> gap(1) / gap(0)
            Traceback (most recent call last):
            ...
            GAPError: Error, Rational operations: <divisor> must not be zero
        """
        cdef Obj result
        try:
            sig_GAP_Enter()
            sig_on()
            result = QUO(self.value, (<GapObj>right).value)
            sig_off()
        finally:
            GAP_Leave()
        return make_any_gap_element(self.parent(), result)

    cpdef _mod_(self, right):
        r"""
        Modulus of two GapObj objects.

        EXAMPLES::

            >>> g1 = gap(5)
            >>> g2 = gap(2)
            >>> g1 % g2
            1

            >>> gap(1) % gap.CyclicGroup(2)
            Traceback (most recent call last):
            ...
            GAPError: Error, no method found!
            Error, no 1st choice method found for `mod' on 2 arguments
        """
        cdef Obj result
        try:
            sig_GAP_Enter()
            sig_on()
            result = MOD(self.value, (<GapObj>right).value)
            sig_off()
        finally:
            GAP_Leave()
        return make_any_gap_element(self.parent(), result)

    cpdef _pow_(self, other):
        r"""
        Exponentiation of two GapObj objects.

        EXAMPLES::

            >>> r = gap(5) ^ 2; r
            25
            >>> parent(r)
            C library interface to GAP
            >>> r = 5 ^ gap(2); r
            25
            >>> parent(r)
            C library interface to GAP
            >>> g, = gap.CyclicGroup(5).GeneratorsOfGroup()
            >>> g ^ 5
            <identity> of ...

        TESTS:

        Check that this can be interrupted gracefully::

            >>> a, b = gap.GL(1000, 3).GeneratorsOfGroup(); g = a * b
            >>> alarm(0.5); g ^ (2 ^ 10000)
            Traceback (most recent call last):
            ...
            AlarmInterrupt

            >>> gap.CyclicGroup(2) ^ 2
            Traceback (most recent call last):
            ...
            GAPError: Error, no method found!
            Error, no 1st choice method found for `^' on 2 arguments

            >>> gap(3) ^ Infinity
            Traceback (most recent call last):
            ...
            GAPError: Error, no method found! Error, no 1st choice
            method found for `InverseMutable' on 1 arguments
        """
        try:
            sig_GAP_Enter()
            sig_on()
            result = POW(self.value, (<GapObj>other).value)
            sig_off()
        finally:
            GAP_Leave()
        return make_any_gap_element(self._parent, result)

    cpdef _pow_int(self, other):
        """
        TESTS::

            >>> gap(5)._pow_int(int(2))
            25
        """
        return self._pow_(self._parent(other))

    def is_function(self):
        """
        Return whether the wrapped GAP object is a function.

        OUTPUT:

        Boolean.

        EXAMPLES::

            >>> a = gap.eval("NormalSubgroups")
            >>> a.is_function()
            True
            >>> a = gap(2/3)
            >>> a.is_function()
            False
        """
        return IS_FUNC(self.value)

    def is_list(self):
        r"""
        Return whether the wrapped GAP object is a GAP List.

        OUTPUT:

        Boolean.

        EXAMPLES::

            >>> gap.eval('[1, 2,,,, 5]').is_list()
            True
            >>> gap.eval('3/2').is_list()
            False
        """
        return IS_LIST(self.value)

    def is_record(self):
        r"""
        Return whether the wrapped GAP object is a GAP record.

        OUTPUT:

        Boolean.

        EXAMPLES::

            >>> gap.eval('[1, 2,,,, 5]').is_record()
            False
            >>> gap.eval('rec(a:=1, b:=3)').is_record()
            True
        """
        return IS_REC(self.value)

    cpdef is_bool(self):
        r"""
        Return whether the wrapped GAP object is a GAP boolean.

        OUTPUT:

        Boolean.

        EXAMPLES::

            >>> gap(True).is_bool()
            True
        """
        libgap = self.parent()
        cdef GapObj r_sage = libgap.IsBool(self)
        cdef Obj r_gap = r_sage.value
        return r_gap == GAP_True

    def is_string(self):
        r"""
        Return whether the wrapped GAP object is a GAP string.

        OUTPUT:

        Boolean.

        EXAMPLES::

            >>> gap('this is a string').is_string()
            True
        """
        return IS_STRING(self.value)

    def is_permutation(self):
        r"""
        Return whether the wrapped GAP object is a GAP permutation.

        OUTPUT:

        Boolean.

        EXAMPLES::

            >>> perm = gap.PermList( gap([1,5,2,3,4]) );  perm
            (2,5,4,3)
            >>> perm.is_permutation()
            True
            >>> gap('this is a string').is_permutation()
            False
        """
        return (TNUM_OBJ(self.value) == T_PERM2 or
                TNUM_OBJ(self.value) == T_PERM4)

    def sage(self):
        r"""
        Return the Sage equivalent of the :class:`GapObj`

        EXAMPLES::

            >>> gap(1).sage()
            1
            >>> type(_)
            <type 'sage.rings.integer.Integer'>

            >>> gap(3/7).sage()
            3/7
            >>> type(_)
            <type 'sage.rings.rational.Rational'>

            >>> gap.eval('5 + 7*E(3)').sage()
            7*zeta3 + 5

            >>> gap(Infinity).sage()
            +Infinity
            >>> gap(-Infinity).sage()
            -Infinity

            >>> gap(True).sage()
            True
            >>> gap(False).sage()
            False
            >>> type(_)
            <... 'bool'>

            >>> gap('this is a string').sage()
            'this is a string'
            >>> type(_)
            <... 'str'>

            >>> x = gap.Integers.Indeterminate("x")

            >>> p = x^2 - 2*x + 3
            >>> p.sage()
            x^2 - 2*x + 3
            >>> p.sage().parent()
            Univariate Polynomial Ring in x over Integer Ring

            >>> p = x^-2 + 3*x
            >>> p.sage()
            x^-2 + 3*x
            >>> p.sage().parent()
            Univariate Laurent Polynomial Ring in x over Integer Ring

            >>> p = (3 * x^2 + x) / (x^2 - 2)
            >>> p.sage()
            (3*x^2 + x)/(x^2 - 2)
            >>> p.sage().parent()
            Fraction Field of Univariate Polynomial Ring in x over Integer Ring

        TESTS:

        Check :trac:`30496`::

            >>> x = gap.Integers.Indeterminate("x")

            >>> p = x^2 - 2*x
            >>> p.sage()
            x^2 - 2*x
        """
        if self.value is NULL:
            return None

        if self.IsInfinity():
            from sage.rings.infinity import Infinity
            return Infinity

        elif self.IsNegInfinity():
            from sage.rings.infinity import Infinity
            return -Infinity

        elif self.IsUnivariateRationalFunction():
            var = self.IndeterminateOfUnivariateRationalFunction().String()
            var = var.sage()
            num, den, val = self.CoefficientsOfUnivariateRationalFunction()
            num = num.sage()
            den = den.sage()
            val = val.sage()
            base_ring = cm.common_parent(*(num + den))

            if self.IsUnivariatePolynomial():
                from sage.rings.polynomial.polynomial_ring_constructor import PolynomialRing
                R = PolynomialRing(base_ring, var)
                x = R.gen()
                return x**val * R(num)

            elif self.IsLaurentPolynomial():
                from sage.rings.polynomial.laurent_polynomial_ring import LaurentPolynomialRing
                R = LaurentPolynomialRing(base_ring, var)
                x = R.gen()
                return x**val * R(num)

            else:
                from sage.rings.polynomial.polynomial_ring_constructor import PolynomialRing
                R = PolynomialRing(base_ring, var)
                x = R.gen()
                return x**val * R(num) / R(den)

        elif self.IsList():
            # May be a list-like collection of some other type of GapObjs
            # that we can convert
            return [item.sage() for item in self.AsList()]

        raise NotImplementedError('cannot construct equivalent Sage object')


############################################################################
### GapInteger #############################################################
############################################################################

cdef GapInteger make_GapInteger(parent, Obj obj):
    r"""
    Turn a Gap integer object into a GapInteger Sage object

    EXAMPLES::

        >>> gap(123)
        123
        >>> type(_)
        <type 'sage.libs.gap.element.GapInteger'>
    """
    cdef GapInteger r = GapInteger.__new__(GapInteger)
    r._initialize(parent, obj)
    return r


cdef class GapInteger(GapObj):
    r"""
    Derived class of GapObj for GAP integers.

    EXAMPLES::

        >>> i = gap(123)
        >>> type(i)
        <type 'sage.libs.gap.element.GapInteger'>
        >>> ZZ(i)
        123
    """

    def is_C_int(self):
        r"""
        Return whether the wrapped GAP object is a immediate GAP integer.

        An immediate integer is one that is stored as a C integer, and
        is subject to the usual size limits. Larger integers are
        stored in GAP as GMP integers.

        OUTPUT:

        Boolean.

        EXAMPLES::

            >>> n = gap(1)
            >>> type(n)
            <type 'sage.libs.gap.element.GapInteger'>
            >>> n.is_C_int()
            True
            >>> n.IsInt()
            true

            >>> N = gap(2^130)
            >>> type(N)
            <type 'sage.libs.gap.element.GapInteger'>
            >>> N.is_C_int()
            False
            >>> N.IsInt()
            true
        """
        return IS_INTOBJ(self.value)

    def _rational_(self):
        r"""
        EXAMPLES::

            >>> QQ(gap(1))  # indirect doctest
            1
            >>> QQ(gap(-2**200)) == -2**200
            True
        """
        return self.sage(ring=QQ)

    def sage(self, ring=None):
        r"""
        Return the Sage equivalent of the :class:`GapInteger`

        - ``ring`` -- Integer ring or ``None`` (default). If not
          specified, a the default Sage integer ring is used.

        OUTPUT:

        A Sage integer

        EXAMPLES::

            >>> gap([ 1, 3, 4 ]).sage()
            [1, 3, 4]
            >>> all( x in ZZ for x in _ )
            True

            >>> gap(132).sage(ring=IntegerModRing(13))
            2
            >>> parent(_)
            Ring of integers modulo 13

        TESTS::

            >>> large = gap.eval('2^130');  large
            1361129467683753853853498429727072845824
            >>> large.sage()
            1361129467683753853853498429727072845824

            >>> huge = gap.eval('10^9999');  huge     # gap abbreviates very long ints
            <integer 100...000 (10000 digits)>
            >>> huge.sage().ndigits()
            10000
        """
        if ring is None:
            ring = ZZ
        if self.is_C_int():
            return ring(INT_INTOBJ(self.value))
        else:
            # TODO: waste of time!
            # gap integers are stored as a mp_limb_t and we have a much more direct
            # conversion implemented in mpz_get_pylong(mpz_srcptr z)
            # (see sage.libs.gmp.pylong)
            string = self.String().sage()
            return ring(string)

    _integer_ = sage

    def __int__(self):
        r"""
        TESTS::

            >>> int(gap(3))
            3
            >>> type(_)
            <type 'int'>

            >>> int(gap(2)**128)
            340282366920938463463374607431768211456L
            >>> type(_)  # py2
            <type 'long'>
            >>> type(_)  # py3
            <class 'int'>
        """
        return self.sage(ring=int)

    def __index__(self):
        r"""
        TESTS:

        Check that gap integers can be used as indices (:trac:`23878`)::

            >>> s = 'abcd'
            >>> s[gap(1)]
            'b'
        """
        return int(self)


##########################################################################
### GapFloat #############################################################
##########################################################################

cdef GapFloat make_GapFloat(parent, Obj obj):
    r"""
    Turn a Gap macfloat object into a GapFloat Sage object

    EXAMPLES::

        >>> gap(123.5)
        123.5
        >>> type(_)
        <type 'sage.libs.gap.element.GapFloat'>
    """
    cdef GapFloat r = GapFloat.__new__(GapFloat)
    r._initialize(parent, obj)
    return r

cdef class GapFloat(GapObj):
    r"""
    Derived class of GapObj for GAP floating point numbers.

    EXAMPLES::

        >>> i = gap(123.5)
        >>> type(i)
        <type 'sage.libs.gap.element.GapFloat'>
        >>> RDF(i)
        123.5
        >>> float(i)
        123.5

    TESTS::

        >>> a = RDF.random_element()
        >>> gap(a).sage() == a
        True
    """
    def sage(self, ring=None):
        r"""
        Return the Sage equivalent of the :class:`GapFloat`

        - ``ring`` -- a floating point field or ``None`` (default). If not
          specified, the default Sage ``RDF`` is used.

        OUTPUT:

        A Sage double precision floating point number

        EXAMPLES::

            >>> a = gap.eval("Float(3.25)").sage()
            >>> a
            3.25
            >>> parent(a)
            Real Double Field
        """
        if ring is None:
            ring = RDF
        return ring(VAL_MACFLOAT(self.value))

    def __float__(self):
        r"""
        TESTS::

            >>> float(gap.eval("Float(3.5)"))
            3.5
        """
        return VAL_MACFLOAT(self.value)



############################################################################
### GapIntegerMod ##########################################################
############################################################################

cdef GapIntegerMod make_GapIntegerMod(parent, Obj obj):
    r"""
    Turn a Gap integer object into a :class:`GapIntegerMod` Sage object

    EXAMPLES::

        >>> n = IntegerModRing(123)(13)
        >>> gap(n)
        ZmodnZObj( 13, 123 )
        >>> type(_)
        <type 'sage.libs.gap.element.GapIntegerMod'>
    """
    cdef GapIntegerMod r = GapIntegerMod.__new__(GapIntegerMod)
    r._initialize(parent, obj)
    return r

cdef class GapIntegerMod(GapObj):
    r"""
    Derived class of GapObj for GAP integers modulo an integer.

    EXAMPLES::

        >>> n = IntegerModRing(123)(13)
        >>> i = gap(n)
        >>> type(i)
        <type 'sage.libs.gap.element.GapIntegerMod'>
    """

    cpdef GapInteger lift(self):
        """
        Return an integer lift.

        OUTPUT:

        A :class:`GapInteger` that equals ``self`` in the integer mod ring.

        EXAMPLES::

            >>> n = gap.eval('One(ZmodnZ(123)) * 13')
            >>> n.lift()
            13
            >>> type(_)
            <type 'sage.libs.gap.element.GapInteger'>
        """
        return self.Int()


    def sage(self, ring=None):
        r"""
        Return the Sage equivalent of the :class:`GapIntegerMod`

        INPUT:

        - ``ring`` -- Sage integer mod ring or ``None`` (default). If
          not specified, a suitable integer mod ringa is used
          automatically.

        OUTPUT:

        A Sage integer modulo another integer.

        EXAMPLES::

            >>> n = gap.eval('One(ZmodnZ(123)) * 13')
            >>> n.sage()
            13
            >>> parent(_)
            Ring of integers modulo 123
        """
        if ring is None:
            # ring = self.DefaultRing().sage()
            characteristic = self.Characteristic().sage()
            ring = ZZ.quotient_ring(characteristic)
        return self.lift().sage(ring=ring)


############################################################################
### GapFiniteField #########################################################
############################################################################

cdef GapFiniteField make_GapFiniteField(parent, Obj obj):
    r"""
    Turn a GAP finite field object into a :class:`GapFiniteField` Sage object

    EXAMPLES::

        >>> gap.eval('Z(5)^2')
        Z(5)^2
        >>> type(_)
        <type 'sage.libs.gap.element.GapFiniteField'>
    """
    cdef GapFiniteField r = GapFiniteField.__new__(GapFiniteField)
    r._initialize(parent, obj)
    return r


cdef class GapFiniteField(GapObj):
    r"""
    Derived class of GapObj for GAP finite field elements.

    EXAMPLES::

        >>> gap.eval('Z(5)^2')
        Z(5)^2
        >>> type(_)
        <type 'sage.libs.gap.element.GapFiniteField'>
    """

    cpdef GapInteger lift(self):
        """
        Return an integer lift.

        OUTPUT:

        The smallest positive :class:`GapInteger` that equals
        ``self`` in the prime finite field.

        EXAMPLES::

            >>> n = gap.eval('Z(5)^2')
            >>> n.lift()
            4
            >>> type(_)
            <type 'sage.libs.gap.element.GapInteger'>

            >>> n = gap.eval('Z(25)')
            >>> n.lift()
            Traceback (most recent call last):
            TypeError: not in prime subfield
        """
        degree = self.DegreeFFE().sage()
        if degree == 1:
            return self.IntFFE()
        else:
            raise TypeError('not in prime subfield')


    def sage(self, ring=None, var='a'):
        r"""
        Return the Sage equivalent of the :class:`GapFiniteField`.

        INPUT:

        - ``ring`` -- a Sage finite field or ``None`` (default). The
          field to return ``self`` in. If not specified, a suitable
          finite field will be constructed.

        OUTPUT:

        An Sage finite field element. The isomorphism is chosen such
        that the Gap ``PrimitiveRoot()`` maps to the Sage
        :meth:`~sage.rings.finite_rings.finite_field_prime_modn.multiplicative_generator`.

        EXAMPLES::

            >>> n = gap.eval('Z(25)^2')
            >>> n.sage()
            a + 3
            >>> parent(_)
            Finite Field in a of size 5^2

            >>> n.sage(ring=GF(5))
            Traceback (most recent call last):
            ...
            ValueError: the given ring is incompatible ...

        TESTS::

            >>> n = gap.eval('Z(2^4)^2 + Z(2^4)^1 + Z(2^4)^0')
            >>> n
            Z(2^2)^2
            >>> n.sage()
            a + 1
            >>> parent(_)
            Finite Field in a of size 2^2
            >>> n.sage(ring=ZZ)
            Traceback (most recent call last):
            ...
            ValueError: the given ring is incompatible ...
            >>> n.sage(ring=CC)
            Traceback (most recent call last):
            ...
            ValueError: the given ring is incompatible ...
            >>> n.sage(ring=GF(5))
            Traceback (most recent call last):
            ...
            ValueError: the given ring is incompatible ...
            >>> n.sage(ring=GF(2^3))
            Traceback (most recent call last):
            ...
            ValueError: the given ring is incompatible ...
            >>> n.sage(ring=GF(2^2, 'a'))
            a + 1
            >>> n.sage(ring=GF(2^4, 'a'))
            a^2 + a + 1
            >>> n.sage(ring=GF(2^8, 'a'))
            a^7 + a^6 + a^4 + a^2 + a + 1

        Check that :trac:`23153` is fixed::

            >>> n = gap.eval('Z(2^4)^2 + Z(2^4)^1 + Z(2^4)^0')
            >>> n.sage(ring=GF(2^4, 'a'))
            a^2 + a + 1
        """
        deg = self.DegreeFFE().sage()
        char = self.Characteristic().sage()
        if ring is None:
            from sage.rings.finite_rings.finite_field_constructor import GF
            ring = GF(char**deg, name=var)
        elif not (ring.is_field() and ring.is_finite() and \
                  ring.characteristic() == char and ring.degree() % deg == 0):
            raise ValueError(('the given ring is incompatible (must be a '
                              'finite field of characteristic {} and degree '
                              'divisible by {})').format(char, deg))

        if self.IsOne():
            return ring.one()
        if deg == 1 and char == ring.characteristic():
            return ring(self.lift().sage())
        else:
            gap_field = make_GapRing(self.parent(), gap_eval(ring._gap_init_()))
            exp = self.LogFFE(gap_field.PrimitiveRoot())
            return ring.multiplicative_generator() ** exp.sage()

    def __int__(self):
        r"""
        TESTS::

            >>> int(gap.eval("Z(53)"))
            2
        """
        return int(self.Int())

    def _integer_(self, R):
        r"""
        TESTS::

            >>> ZZ(gap.eval("Z(53)"))
            2
        """
        return R(self.Int())


############################################################################
### GapCyclotomic ##########################################################
############################################################################

cdef GapCyclotomic make_GapCyclotomic(parent, Obj obj):
    r"""
    Turn a Gap cyclotomic object into a :class:`GapCyclotomic` Sage
    object.

    EXAMPLES::

        >>> gap.eval('E(3)')
        E(3)
        >>> type(_)
        <type 'sage.libs.gap.element.GapCyclotomic'>
    """
    cdef GapCyclotomic r = GapCyclotomic.__new__(GapCyclotomic)
    r._initialize(parent, obj)
    return r


cdef class GapCyclotomic(GapObj):
    r"""
    Derived class of GapObj for GAP universal cyclotomics.

    EXAMPLES::

        >>> gap.eval('E(3)')
        E(3)
        >>> type(_)
        <type 'sage.libs.gap.element.GapCyclotomic'>
    """

    def sage(self, ring=None):
        r"""
        Return the Sage equivalent of the :class:`GapCyclotomic`.

        INPUT:

        - ``ring`` -- a Sage cyclotomic field or ``None``
          (default). If not specified, a suitable minimal cyclotomic
          field will be constructed.

        OUTPUT:

        A Sage cyclotomic field element.

        EXAMPLES::

            >>> n = gap.eval('E(3)')
            >>> n.sage()
            zeta3
            >>> parent(_)
            Cyclotomic Field of order 3 and degree 2

            >>> n.sage(ring=CyclotomicField(6))
            zeta6 - 1

            >>> gap.E(3).sage(ring=CyclotomicField(3))
            zeta3
            >>> gap.E(3).sage(ring=CyclotomicField(6))
            zeta6 - 1

        TESTS:

        Check that :trac:`15204` is fixed::

            >>> gap.E(3).sage(ring=UniversalCyclotomicField())
            E(3)
            >>> gap.E(3).sage(ring=CC)
            -0.500000000000000 + 0.866025403784439*I
        """
        if ring is None:
            conductor = self.Conductor()
            from sage.rings.number_field.number_field import CyclotomicField
            ring = CyclotomicField(conductor.sage())
        else:
            try:
                conductor = ring._n()
            except AttributeError:
                from sage.rings.number_field.number_field import CyclotomicField
                conductor = self.Conductor()
                cf = CyclotomicField(conductor.sage())
                return ring(cf(self.CoeffsCyc(conductor).sage()))
        coeff = self.CoeffsCyc(conductor).sage()
        return ring(coeff)


############################################################################
### GapRational ############################################################
############################################################################

cdef GapRational make_GapRational(parent, Obj obj):
    r"""
    Turn a Gap Rational number (of type ``Obj``) into a Cython ``GapRational``.

    EXAMPLES::

        >>> gap(123/456)
        41/152
        >>> type(_)
        <type 'sage.libs.gap.element.GapRational'>
    """
    cdef GapRational r = GapRational.__new__(GapRational)
    r._initialize(parent, obj)
    return r


cdef class GapRational(GapObj):
    r"""
    Derived class of GapObj for GAP rational numbers.

    EXAMPLES::

        >>> r = gap(123/456)
        >>> type(r)
        <type 'sage.libs.gap.element.GapRational'>
    """
    def _rational_(self):
        r"""
        EXAMPLES::

            >>> r = gap(-1/3)
            >>> QQ(r)  # indirect doctest
            -1/3
            >>> QQ(gap(2**300 / 3**300)) == 2**300 / 3**300
            True
        """
        return self.sage(ring=QQ)

    def sage(self, ring=None):
        r"""
        Return the Sage equivalent of the :class:`GapObj`.

        INPUT:

        - ``ring`` -- the Sage rational ring or ``None`` (default). If
          not specified, the rational ring is used automatically.

        OUTPUT:

        A Sage rational number.

        EXAMPLES::

            >>> r = gap(123/456);  r
            41/152
            >>> type(_)
            <type 'sage.libs.gap.element.GapRational'>
            >>> r.sage()
            41/152
            >>> type(_)
            <type 'sage.rings.rational.Rational'>
        """
        if ring is None:
            ring = ZZ
        libgap = self.parent()
        return libgap.NumeratorRat(self).sage(ring=ring) / libgap.DenominatorRat(self).sage(ring=ring)


############################################################################
### GapRing ################################################################
############################################################################

cdef GapRing make_GapRing(parent, Obj obj):
    r"""
    Turn a Gap integer object into a :class:`GapRing` Sage object.

    EXAMPLES::

        >>> gap(GF(5))
        GF(5)
        >>> type(_)
        <type 'sage.libs.gap.element.GapRing'>
    """
    cdef GapRing r = GapRing.__new__(GapRing)
    r._initialize(parent, obj)
    return r


cdef class GapRing(GapObj):
    r"""
    Derived class of GapObj for GAP rings (parents of ring elements).

    EXAMPLES::

        >>> i = gap(ZZ)
        >>> type(i)
        <type 'sage.libs.gap.element.GapRing'>
    """

    def ring_integer(self):
        """
        Construct the Sage integers.

        EXAMPLES::

            >>> gap.eval('Integers').ring_integer()
            Integer Ring
        """
        return ZZ

    def ring_rational(self):
        """
        Construct the Sage rationals.

        EXAMPLES::

            >>> gap.eval('Rationals').ring_rational()
            Rational Field
        """
        return ZZ.fraction_field()

    def ring_integer_mod(self):
        """
        Construct a Sage integer mod ring.

        EXAMPLES::

            >>> gap.eval('ZmodnZ(15)').ring_integer_mod()
            Ring of integers modulo 15
        """
        characteristic = self.Characteristic().sage()
        return ZZ.quotient_ring(characteristic)


    def ring_finite_field(self, var='a'):
        """
        Construct an integer ring.

        EXAMPLES::

            >>> gap.GF(3,2).ring_finite_field(var='A')
            Finite Field in A of size 3^2
        """
        size = self.Size().sage()
        from sage.rings.finite_rings.finite_field_constructor import GF
        return GF(size, name=var)


    def ring_cyclotomic(self):
        """
        Construct an integer ring.

        EXAMPLES::

            >>> gap.CyclotomicField(6).ring_cyclotomic()
            Cyclotomic Field of order 3 and degree 2
        """
        conductor = self.Conductor()
        from sage.rings.number_field.number_field import CyclotomicField
        return CyclotomicField(conductor.sage())

    def ring_polynomial(self):
        """
        Construct a polynomial ring.

        EXAMPLES::

            >>> B = gap(QQ['x'])
            >>> B.ring_polynomial()
            Univariate Polynomial Ring in x over Rational Field

            >>> B = gap(ZZ['x','y'])
            >>> B.ring_polynomial()
            Multivariate Polynomial Ring in x, y over Integer Ring
        """
        base_ring = self.CoefficientsRing().sage()
        vars = [x.String().sage()
                for x in self.IndeterminatesOfPolynomialRing()]
        from sage.rings.polynomial.polynomial_ring_constructor import PolynomialRing
        return PolynomialRing(base_ring, vars)

    def sage(self, **kwds):
        r"""
        Return the Sage equivalent of the :class:`GapRing`.

        INPUT:

        - ``**kwds`` -- keywords that are passed on to the ``ring_``
          method.

        OUTPUT:

        A Sage ring.

        EXAMPLES::

            >>> gap.eval('Integers').sage()
            Integer Ring

            >>> gap.eval('Rationals').sage()
            Rational Field

            >>> gap.eval('ZmodnZ(15)').sage()
            Ring of integers modulo 15

            >>> gap.GF(3,2).sage(var='A')
            Finite Field in A of size 3^2

            >>> gap.CyclotomicField(6).sage()
            Cyclotomic Field of order 3 and degree 2

            >>> gap(QQ['x','y']).sage()
            Multivariate Polynomial Ring in x, y over Rational Field
        """
        if self.IsField():
            if self.IsRationals():
                return self.ring_rational(**kwds)
            if self.IsCyclotomicField():
                return self.ring_cyclotomic(**kwds)
            if self.IsFinite():
                return self.ring_finite_field(**kwds)
        else:
            if self.IsIntegers():
                return self.ring_integer(**kwds)
            if self.IsFinite():
                return self.ring_integer_mod(**kwds)
            if self.IsPolynomialRing():
                return self.ring_polynomial(**kwds)
        raise NotImplementedError('cannot convert GAP ring to Sage')


############################################################################
### GapBoolean #############################################################
############################################################################

cdef GapBoolean make_GapBoolean(parent, Obj obj):
    r"""
    Turn a Gap Boolean number (of type ``Obj``) into a Cython ``GapBoolean``.

    EXAMPLES::

        >>> gap(True)
        true
        >>> type(_)
        <type 'sage.libs.gap.element.GapBoolean'>
    """
    cdef GapBoolean r = GapBoolean.__new__(GapBoolean)
    r._initialize(parent, obj)
    return r


cdef class GapBoolean(GapObj):
    r"""
    Derived class of GapObj for GAP boolean values.

    EXAMPLES::

        >>> b = gap(True)
        >>> type(b)
        <type 'sage.libs.gap.element.GapBoolean'>
    """

    def sage(self):
        r"""
        Return the Sage equivalent of the :class:`GapObj`

        OUTPUT:

        A Python boolean if the values is either true or false. GAP
        booleans can have the third value ``Fail``, in which case a
        ``ValueError`` is raised.

        EXAMPLES::

            >>> b = gap.eval('true');  b
            true
            >>> type(_)
            <type 'sage.libs.gap.element.GapBoolean'>
            >>> b.sage()
            True
            >>> type(_)
            <... 'bool'>

            >>> gap.eval('fail')
            fail
            >>> _.sage()
            Traceback (most recent call last):
            ...
            ValueError: the GAP boolean value "fail" cannot be represented in Sage
        """
        if self.value == GAP_True:
            return True
        if self.value == GAP_False:
            return False
        raise ValueError('the GAP boolean value "fail" cannot be represented in Sage')

    def __nonzero__(self):
        """
        Check that the boolean is "true".

        This is syntactic sugar for using libgap. See the examples below.

        OUTPUT:

        Boolean.

        EXAMPLES::

            >>> gap_bool = [gap.eval('true'), gap.eval('false'), gap.eval('fail')]
            >>> for x in gap_bool:
            ...     if x:     # this calls __nonzero__
            ...         print("{} {}".format(x, type(x)))
            true <type 'sage.libs.gap.element.GapBoolean'>

            >>> for x in gap_bool:
            ...     if not x:     # this calls __nonzero__
            ...         print("{} {}".format( x, type(x)))
            false <type 'sage.libs.gap.element.GapBoolean'>
            fail <type 'sage.libs.gap.element.GapBoolean'>
        """
        return self.value == GAP_True


############################################################################
### GapString ##############################################################
############################################################################

cdef GapString make_GapString(parent, Obj obj):
    r"""
    Turn a Gap String (of type ``Obj``) into a Cython ``GapString``.

    EXAMPLES::

        >>> gap('this is a string')
        "this is a string"
        >>> type(_)
        <type 'sage.libs.gap.element.GapString'>
    """
    cdef GapString r = GapString.__new__(GapString)
    r._initialize(parent, obj)
    return r


cdef class GapString(GapObj):
    r"""
    Derived class of GapObj for GAP strings.

    EXAMPLES::

        >>> s = gap('string')
        >>> type(s)
        <type 'sage.libs.gap.element.GapString'>
        >>> s
        "string"
        >>> print(s)
        string
    """
    def __str__(self):
        r"""
        Convert this :class:`GapString` to a Python string.

        OUTPUT:

        A Python string.

        EXAMPLES::

            >>> s = gap.eval(' "string" '); s
            "string"
            >>> type(_)
            <type 'sage.libs.gap.element.GapString'>
            >>> str(s)
            'string'
            >>> s.sage()
            'string'
            >>> type(_)
            <type 'str'>
        """
        s = char_to_str(CSTR_STRING(self.value))
        return s

    sage = __str__

############################################################################
### GapFunction ############################################################
############################################################################

cdef GapFunction make_GapFunction(parent, Obj obj):
    r"""
    Turn a Gap C function object (of type ``Obj``) into a Cython ``GapFunction``.

    INPUT:

    - ``parent`` -- the parent of the new :class:`GapObj`

    - ``obj`` -- a GAP function object.

    OUTPUT:

    A :class:`GapFunction` instance.

    EXAMPLES::

        >>> gap.CycleLength
        <Gap function "CycleLength">
        >>> type(_)
        <type 'sage.libs.gap.element.GapFunction'>
    """
    cdef GapFunction r = GapFunction.__new__(GapFunction)
    r._initialize(parent, obj)
    return r


cdef class GapFunction(GapObj):
    r"""
    Derived class of GapObj for GAP functions.

    EXAMPLES::

        >>> f = gap.Cycles
        >>> type(f)
        <type 'sage.libs.gap.element.GapFunction'>
    """


    def __repr__(self):
        r"""
        Return a string representation

        OUTPUT:

        String.

        EXAMPLES::

            >>> gap.Orbits
            <Gap function "Orbits">
        """
        libgap = self.parent()
        name = libgap.NameFunction(self)
        s = '<Gap function "'+name.sage()+'">'
        return s


    def __call__(self, *args):
        """
        Call syntax for functions.

        INPUT:

        - ``*args`` -- arguments. Will be converted to `GapObj` if
          they are not already of this type.

        OUTPUT:

        A :class:`GapObj` encapsulating the functions return
        value, or ``None`` if it does not return anything.

        EXAMPLES::

            >>> a = gap.NormalSubgroups
            >>> b = gap.SymmetricGroup(4)
            >>> gap.collect()
            >>> a
            <Gap function "NormalSubgroups">
            >>> b
            Sym( [ 1 .. 4 ] )
            >>> sorted(a(b))
            [Group(()),
             Sym( [ 1 .. 4 ] ),
             Alt( [ 1 .. 4 ] ),
             Group([ (1,4)(2,3), (1,2)(3,4) ])]

            >>> gap.eval("a := NormalSubgroups")
            <Gap function "NormalSubgroups">
            >>> gap.eval("b := SymmetricGroup(4)")
            Sym( [ 1 .. 4 ] )
            >>> gap.collect()
            >>> sorted(gap.eval('a') (gap.eval('b')))
            [Group(()),
             Sym( [ 1 .. 4 ] ),
             Alt( [ 1 .. 4 ] ),
             Group([ (1,4)(2,3), (1,2)(3,4) ])]

            >>> a = gap.eval('a')
            >>> b = gap.eval('b')
            >>> gap.collect()
            >>> sorted(a(b))
            [Group(()),
             Sym( [ 1 .. 4 ] ),
             Alt( [ 1 .. 4 ] ),
             Group([ (1,4)(2,3), (1,2)(3,4) ])]

        Not every ``GapObj`` is callable::

            >>> f = gap(3)
            >>> f()
            Traceback (most recent call last):
            ...
            TypeError: 'sage.libs.gap.element.GapInteger' object is not callable

        We illustrate appending to a list which returns None::

            >>> a = gap([]); a
            [  ]
            >>> a.Add(5); a
            [ 5 ]
            >>> a.Add(10); a
            [ 5, 10 ]

        TESTS::

            >>> s = gap.Sum
            >>> s(gap([1,2]))
            3
            >>> s(gap(1), gap(2))
            Traceback (most recent call last):
            ...
            GAPError: Error, no method found!
            Error, no 1st choice method found for `SumOp' on 2 arguments

            >>> for i in range(0,100):
            ...     rnd = [ randint(-10,10) for i in range(0,randint(0,7)) ]
            ...     # compute the sum in GAP
            ...     _ = gap.Sum(rnd)
            ...     try:
            ...         gap.Sum(*rnd)
            ...         print('This should have triggered a ValueError')
            ...         print('because Sum needs a list as argument')
            ...     except ValueError:
            ...         pass

            >>> gap_exec = gap.eval("Exec")
            >>> gap_exec('echo hello from the shell')
            hello from the shell
        """
        cdef Obj result = NULL
        cdef Obj arg_list
        cdef int i, n = len(args)

        libgap = self.parent()

        if n > 0:
            a = [x if isinstance(x, GapObj) else libgap(x) for x in args]

        try:
            sig_GAP_Enter()
            sig_on()
            if n == 0:
                result = CALL_0ARGS(self.value)
            elif n == 1:
                result = CALL_1ARGS(self.value,
                                           (<GapObj>a[0]).value)
            elif n == 2:
                result = CALL_2ARGS(self.value,
                                           (<GapObj>a[0]).value,
                                           (<GapObj>a[1]).value)
            elif n == 3:
                result = CALL_3ARGS(self.value,
                                           (<GapObj>a[0]).value,
                                           (<GapObj>a[1]).value,
                                           (<GapObj>a[2]).value)
            elif n == 4:
                result = CALL_4ARGS(self.value,
                                           (<GapObj>a[0]).value,
                                           (<GapObj>a[1]).value,
                                           (<GapObj>a[2]).value,
                                           (<GapObj>a[3]).value)
            elif n == 5:
                result = CALL_5ARGS(self.value,
                                           (<GapObj>a[0]).value,
                                           (<GapObj>a[1]).value,
                                           (<GapObj>a[2]).value,
                                           (<GapObj>a[3]).value,
                                           (<GapObj>a[4]).value)
            elif n == 6:
                result = CALL_6ARGS(self.value,
                                           (<GapObj>a[0]).value,
                                           (<GapObj>a[1]).value,
                                           (<GapObj>a[2]).value,
                                           (<GapObj>a[3]).value,
                                           (<GapObj>a[4]).value,
                                           (<GapObj>a[5]).value)
            elif n >= 7:
                arg_list = make_gap_list(libgap, args)
                result = CALL_XARGS(self.value, arg_list)
            sig_off()
        finally:
            GAP_Leave()
        if result == NULL:
            # We called a procedure that does not return anything
            return None
        return make_any_gap_element(libgap, result)



    def _instancedoc_(self):
        r"""
        Return the help string

        EXAMPLES::

            >>> f = gap.CyclicGroup
            >>> 'constructs  the  cyclic  group' in f.__doc__
            True

        You would get the full help by typing ``f?`` in the command line.
        """
        libgap = self.parent()
        from sage.interfaces.gap import gap
        return gap.help(libgap.NameFunction(self).sage(), pager=False)




############################################################################
### GapMethodProxy #########################################################
############################################################################

cdef GapMethodProxy make_GapMethodProxy(parent, Obj function, GapObj base_object):
    r"""
    Turn a Gap C rec object (of type ``Obj``) into a Cython ``GapRecord``.

    This class implement syntactic sugar so that you can write
    ``gapelement.f()`` instead of ``gap.f(gapelement)`` for any GAP
    function ``f``.

    INPUT:

    - ``parent`` -- the parent of the new :class:`GapObj`

    - ``obj`` -- a GAP function object.

    - ``base_object`` -- The first argument to be inserted into the function.

    OUTPUT:

    A :class:`GapMethodProxy` instance.

    EXAMPLES::

        >>> lst = gap([])
        >>> type( lst.Add )
        <type 'sage.libs.gap.element.GapMethodProxy'>
    """
    cdef GapMethodProxy r = GapMethodProxy.__new__(GapMethodProxy)
    r._initialize(parent, function)
    r.first_argument = base_object
    return r


cdef class GapMethodProxy(GapFunction):
    r"""
    Helper class returned by ``GapObj.__getattr__``.

    Derived class of GapObj for GAP functions. Like its parent,
    you can call instances to implement function call syntax. The only
    difference is that a fixed first argument is prepended to the
    argument list.

    EXAMPLES::

        >>> lst = gap([])
        >>> lst.Add
        <Gap function "Add">
        >>> type(_)
        <type 'sage.libs.gap.element.GapMethodProxy'>
        >>> lst.Add(1)
        >>> lst
        [ 1 ]
    """

    def __call__(self, *args):
        """
        Call syntax for methods.

        This method is analogous to
        :meth:`GapFunction.__call__`, except that it inserts a
        fixed :class:`GapObj` in the first slot of the function.

        INPUT:

        - ``*args`` -- arguments. Will be converted to `GapObj` if
          they are not already of this type.

        OUTPUT:

        A :class:`GapObj` encapsulating the functions return
        value, or ``None`` if it does not return anything.

        EXAMPLES::

            >>> lst = gap.eval('[1,,3]')
            >>> lst.Add.__call__(4)
            >>> lst.Add(5)
            >>> lst
            [ 1,, 3, 4, 5 ]
        """
        if len(args) > 0:
            return GapFunction.__call__(self, * ([self.first_argument] + list(args)))
        else:
            return GapFunction.__call__(self, self.first_argument)



############################################################################
### GapList ################################################################
############################################################################

cdef GapList make_GapList(parent, Obj obj):
    r"""
    Turn a Gap C List object (of type ``Obj``) into a Cython ``GapList``.

    EXAMPLES::

        >>> gap([0, 2, 3])
        [ 0, 2, 3 ]
        >>> type(_)
        <type 'sage.libs.gap.element.GapList'>
    """
    cdef GapList r = GapList.__new__(GapList)
    r._initialize(parent, obj)
    return r


cdef class GapList(GapObj):
    r"""
    Derived class of GapObj for GAP Lists.

    .. NOTE::

        Lists are indexed by `0..len(l)-1`, as expected from
        Python. This differs from the GAP convention where lists start
        at `1`.

    EXAMPLES::

        >>> lst = gap.SymmetricGroup(3).List(); lst
        [ (), (1,3), (1,2,3), (2,3), (1,3,2), (1,2) ]
        >>> type(lst)
        <type 'sage.libs.gap.element.GapList'>
        >>> len(lst)
        6
        >>> lst[3]
        (2,3)

    We can easily convert a Gap ``List`` object into a Python ``list``::

        >>> list(lst)
        [(), (1,3), (1,2,3), (2,3), (1,3,2), (1,2)]
        >>> type(_)
        <... 'list'>

    Range checking is performed::

        >>> lst[10]
        Traceback (most recent call last):
        ...
        IndexError: index out of range.
    """

    def __bool__(self):
        r"""
        Return True if the list is non-empty, as with Python ``list``s.

        EXAMPLES::

            >>> lst = gap.eval('[1,,,4]')
            >>> bool(lst)
            True
            >>> lst = gap.eval('[]')
            >>> bool(lst)
            False
        """
        return bool(len(self))

    def __len__(self):
        r"""
        Return the length of the list.

        OUTPUT:

        Integer.

        EXAMPLES::

            >>> lst = gap.eval('[1,,,4]')   # a sparse list
            >>> len(lst)
            4
        """
        return LEN_LIST(self.value)

    def __getitem__(self, i):
        r"""
        Return the ``i``-th element of the list.

        As usual in Python, indexing starts at `0` and not at `1` (as
        in GAP). This can also be used with multi-indices.

        INPUT:

        - ``i`` -- integer.

        OUTPUT:

        The ``i``-th element as a :class:`GapObj`.

        EXAMPLES::

            >>> lst = gap.eval('["first",,,"last"]')   # a sparse list
            >>> lst[0]
            "first"

            >>> l = gap.eval('[ [0, 1], [2, 3] ]')
            >>> l[0,0]
            0
            >>> l[0,1]
            1
            >>> l[1,0]
            2
            >>> l[0,2]
            Traceback (most recent call last):
            ...
            IndexError: index out of range
            >>> l[2,0]
            Traceback (most recent call last):
            ...
            IndexError: index out of range
            >>> l[0,0,0]
            Traceback (most recent call last):
            ...
            ValueError: too many indices
        """
        cdef int j
        cdef Obj obj = self.value

        if isinstance(i, tuple):
            for j in i:
                if not IS_LIST(obj):
                    raise ValueError('too many indices')
                if j < 0 or j >= LEN_LIST(obj):
                    raise IndexError('index out of range')
                obj = ELM_LIST(obj, j+1)

        else:
            j = i
            if j < 0 or j >= LEN_LIST(obj):
                raise IndexError('index out of range.')
            obj = ELM_LIST(obj, j+1)

        return make_any_gap_element(self.parent(), obj)

    def __setitem__(self, i, elt):
        r"""
        Set the ``i``-th item of this list

        EXAMPLES::

            >>> l = gap.eval('[0, 1]')
            >>> l
            [ 0, 1 ]
            >>> l[0] = 3
            >>> l
            [ 3, 1 ]

        Contrarily to Python lists, setting an element beyond the limit extends the list::

            >>> l[12] = -2
            >>> l
            [ 3, 1,,,,,,,,,,, -2 ]

        This function also handles multi-indices::

            >>> l = gap.eval('[[[0,1],[2,3]],[[4,5], [6,7]]]')
            >>> l[0,1,0] = -18
            >>> l
            [ [ [ 0, 1 ], [ -18, 3 ] ], [ [ 4, 5 ], [ 6, 7 ] ] ]
            >>> l[0,0,0,0]
            Traceback (most recent call last):
            ...
            ValueError: too many indices

        Assignment to immutable objects gives error::

            >>> l = gap([0,1])
            >>> u = l.deepcopy(0)
            >>> u[0] = 5
            Traceback (most recent call last):
            ...
            TypeError: immutable Gap object does not support item assignment

        TESTS::

            >>> m = gap.eval('[[0,0],[0,0]]')
            >>> m[0,0] = 1
            >>> m[0,1] = 2
            >>> m[1,0] = 3
            >>> m[1,1] = 4
            >>> m
            [ [ 1, 2 ], [ 3, 4 ] ]
        """
        if not IS_MUTABLE_OBJ(self.value):
            raise TypeError('immutable Gap object does not support item assignment')

        cdef int j
        cdef Obj obj = self.value

        if isinstance(i, tuple):
            for j in i[:-1]:
                if not IS_LIST(obj):
                    raise ValueError('too many indices')
                if j < 0 or j >= LEN_LIST(obj):
                    raise IndexError('index out of range')
                obj = ELM_LIST(obj, j+1)
            if not IS_LIST(obj):
                raise ValueError('too many indices')
            j = i[-1]
        else:
            j = i

        if j < 0:
            raise IndexError('index out of range.')

        cdef GapObj celt
        if isinstance(elt, GapObj):
            celt = <GapObj> elt
        else:
            celt= self.parent()(elt)

        ASS_LIST(obj, j+1, celt.value)

    def sage(self, **kwds):
        r"""
        Return the Sage equivalent of the :class:`GapObj`

        OUTPUT:

        A Python list.

        EXAMPLES::

            >>> gap([ 1, 3, 4 ]).sage()
            [1, 3, 4]
            >>> all( x in ZZ for x in _ )
            True
        """
        return [ x.sage(**kwds) for x in self ]


    def matrix(self, ring=None):
        """
        Return the list as a matrix.

        GAP does not have a special matrix data type, they are just
        lists of lists. This function converts a GAP list of lists to
        a Sage matrix.

        OUTPUT:

        A Sage matrix.

        EXAMPLES::

            >>> F = gap.GF(4)
            >>> a = F.PrimitiveElement()
            >>> m = gap([[a,a^0],[0*a,a^2]]); m
            [ [ Z(2^2), Z(2)^0 ],
              [ 0*Z(2), Z(2^2)^2 ] ]
            >>> m.IsMatrix()
            true
            >>> matrix(m)
            [    a     1]
            [    0 a + 1]
            >>> matrix(GF(4,'B'), m)
            [    B     1]
            [    0 B + 1]

            >>> M = gap.eval('SL(2,GF(5))').GeneratorsOfGroup()[1]
            >>> type(M)
            <type 'sage.libs.gap.element.GapList'>
            >>> M[0][0]
            Z(5)^2
            >>> M.IsMatrix()
            true
            >>> M.matrix()
            [4 1]
            [4 0]
        """
        if not self.IsMatrix():
            raise ValueError('not a GAP matrix')
        entries = self.Flat()
        n = self.Length().sage()
        m = len(entries) // n
        if len(entries) % n != 0:
            raise ValueError('not a rectangular list of lists')
        from sage.matrix.matrix_space import MatrixSpace
        if ring is None:
            ring = entries.DefaultRing().sage()
        MS = MatrixSpace(ring, n, m)
        return MS([x.sage(ring=ring) for x in entries])

    _matrix_ = matrix

    def vector(self, ring=None):
        """
        Return the list as a vector.

        GAP does not have a special vector data type, they are just
        lists. This function converts a GAP list to a Sage vector.

        OUTPUT:

        A Sage vector.

        EXAMPLES::

            >>> F = gap.GF(4)
            >>> a = F.PrimitiveElement()
            >>> m = gap([0*a, a, a^3, a^2]); m
            [ 0*Z(2), Z(2^2), Z(2)^0, Z(2^2)^2 ]
            >>> type(m)
            <type 'sage.libs.gap.element.GapList'>
            >>> m[3]
            Z(2^2)^2
            >>> vector(m)
            (0, a, 1, a + 1)
            >>> vector(GF(4,'B'), m)
            (0, B, 1, B + 1)
        """
        if not self.IsVector():
            raise ValueError('not a GAP vector')
        from sage.modules.all import vector
        entries = self.Flat()
        n = self.Length().sage()
        if ring is None:
            ring = entries.DefaultRing().sage()
        return vector(ring, n, self.sage(ring=ring))

    _vector_ = vector



############################################################################
### GapPermutation #########################################################
############################################################################


cdef GapPermutation make_GapPermutation(parent, Obj obj):
    r"""
    Turn a Gap C permutation object (of type ``Obj``) into a Cython
    ``GapPermutation``.

    EXAMPLES::

        >>> gap.eval('(1,3,2)(4,5,8)')
        (1,3,2)(4,5,8)
        >>> type(_)
        <type 'sage.libs.gap.element.GapPermutation'>
    """
    cdef GapPermutation r = GapPermutation.__new__(GapPermutation)
    r._initialize(parent, obj)
    return r


cdef class GapPermutation(GapObj):
    r"""
    Derived class of GapObj for GAP permutations.

    .. NOTE::

        Permutations in GAP act on the numbers starting with 1.

    EXAMPLES::

        >>> perm = gap.eval('(1,5,2)(4,3,8)')
        >>> type(perm)
        <type 'sage.libs.gap.element.GapPermutation'>
    """

    def sage(self, parent=None):
        r"""
        Return the Sage equivalent of the :class:`GapObj`

        If the permutation group is given as parent, this method is
        *much* faster.

        EXAMPLES::

            >>> perm_gap = gap.eval('(1,5,2)(4,3,8)');  perm_gap
            (1,5,2)(3,8,4)
            >>> perm_gap.sage()
            [5, 1, 8, 3, 2, 6, 7, 4]
            >>> type(_)
            <class 'sage.combinat.permutation.StandardPermutations_all_with_category.element_class'>
            >>> perm_gap.sage(PermutationGroup([(1,2),(1,2,3,4,5,6,7,8)]))
            (1,5,2)(3,8,4)
            >>> type(_)
            <type 'sage.groups.perm_gps.permgroup_element.PermutationGroupElement'>
        """
        cdef PermutationGroupElement one_c

        libgap = self.parent()
        lst = libgap.ListPerm(self)

        if parent is None:
            return Permutation(lst.sage(), check_input=False)
        else:
            return parent.one()._generate_new_GAP(lst)

############################################################################
### GapRecord ##############################################################
############################################################################

cdef GapRecord make_GapRecord(parent, Obj obj):
    r"""
    Turn a Gap C rec object (of type ``Obj``) into a Cython ``GapRecord``.

    EXAMPLES::

        >>> gap.eval('rec(a:=0, b:=2, c:=3)')
        rec( a := 0, b := 2, c := 3 )
        >>> type(_)
        <type 'sage.libs.gap.element.GapRecord'>
    """
    cdef GapRecord r = GapRecord.__new__(GapRecord)
    r._initialize(parent, obj)
    return r


cdef class GapRecord(GapObj):
    r"""
    Derived class of GapObj for GAP records.

    EXAMPLES::

        >>> rec = gap.eval('rec(a:=123, b:=456)')
        >>> type(rec)
        <type 'sage.libs.gap.element.GapRecord'>
        >>> len(rec)
        2
        >>> rec['a']
        123

    We can easily convert a Gap ``rec`` object into a Python ``dict``::

        >>> dict(rec)
        {'a': 123, 'b': 456}
        >>> type(_)
        <... 'dict'>

    Range checking is performed::

        >>> rec['no_such_element']
        Traceback (most recent call last):
        ...
        GAPError: Error, Record Element: '<rec>.no_such_element' must have an assigned value
    """

    def __len__(self):
        r"""
        Return the length of the record.

        OUTPUT:

        Integer. The number of entries in the record.

        EXAMPLES::

            >>> rec = gap.eval('rec(a:=123, b:=456, S3:=SymmetricGroup(3))')
            >>> len(rec)
            3
        """
        return LEN_PREC(self.value)

    def __iter__(self):
        r"""
        Iterate over the elements of the record.

        OUTPUT:

        A :class:`GapRecordIterator`.

        EXAMPLES::

            >>> rec = gap.eval('rec(a:=123, b:=456)')
            >>> iter = rec.__iter__()
            >>> type(iter)
            <type 'sage.libs.gap.element.GapRecordIterator'>
            >>> sorted(rec)
            [('a', 123), ('b', 456)]
        """
        return GapRecordIterator(self)

    cpdef UInt record_name_to_index(self, name):
        r"""
        Convert string to GAP record index.

        INPUT:

        - ``py_name`` -- a python string.

        OUTPUT:

        A ``UInt``, which is a GAP hash of the string. If this is the
        first time the string is encountered, a new integer is
        returned(!)

        EXAMPLES::

            >>> rec = gap.eval('rec(first:=123, second:=456)')
            >>> rec.record_name_to_index('first')   # random output
            1812L
            >>> rec.record_name_to_index('no_such_name') # random output
            3776L
        """
        name = str_to_bytes(name)
        return RNamName(name)

    def __getitem__(self, name):
        r"""
        Return the ``name``-th element of the GAP record.

        INPUT:

        - ``name`` -- string.

        OUTPUT:

        The record element labelled by ``name`` as a :class:`GapObj`.

        EXAMPLES::

            >>> rec = gap.eval('rec(first:=123, second:=456)')
            >>> rec['first']
            123
        """
        cdef UInt i = self.record_name_to_index(name)
        cdef Obj result
        sig_on()
        try:
            GAP_Enter()
            result = ELM_REC(self.value, i)
        finally:
            GAP_Leave()
            sig_off()
        return make_any_gap_element(self.parent(), result)

    def sage(self):
        r"""
        Return the Sage equivalent of the :class:`GapObj`

        EXAMPLES::

            >>> gap.eval('rec(a:=1, b:=2)').sage()
            {'a': 1, 'b': 2}
            >>> all( isinstance(key,str) and val in ZZ for key,val in _.items() )
            True

            >>> rec = gap.eval('rec(a:=123, b:=456, Sym3:=SymmetricGroup(3))')
            >>> rec.sage()
            {'Sym3': NotImplementedError('cannot construct equivalent Sage object'...),
             'a': 123,
             'b': 456}
        """
        result = {}
        for key, val in self:
            try:
                val = val.sage()
            except Exception as ex:
                val = ex
            result[key] = val
        return result


cdef class GapRecordIterator(object):
    r"""
    Iterator for :class:`GapRecord`

    Since Cython does not support generators yet, we implement the
    older iterator specification with this auxiliary class.

    INPUT:

    - ``rec`` -- the :class:`GapRecord` to iterate over.

    EXAMPLES::

        >>> rec = gap.eval('rec(a:=123, b:=456)')
        >>> sorted(rec)
        [('a', 123), ('b', 456)]
        >>> dict(rec)
        {'a': 123, 'b': 456}
    """

    def __cinit__(self, rec):
        r"""
        The Cython constructor.

        INPUT:

        - ``rec`` -- the :class:`GapRecord` to iterate over.

        EXAMPLES::

            >>> gap.eval('rec(a:=123, b:=456)')
            rec( a := 123, b := 456 )
        """
        self.rec = rec
        self.i = 1


    def __next__(self):
        r"""
        Return the next element in the record.

        OUTPUT:

        A tuple ``(key, value)`` where ``key`` is a string and
        ``value`` is the corresponding :class:`GapObj`.

        EXAMPLES::

            >>> rec = gap.eval('rec(a:=123, b:=456)')
            >>> iter = rec.__iter__()
            >>> a = iter.__next__()
            >>> b = next(iter)
            >>> sorted([a, b])
            [('a', 123), ('b', 456)]
        """
        cdef UInt i = self.i
        if i>len(self.rec):
            raise StopIteration
        # note the abs: negative values mean the rec keys are not sorted
        key_index = abs(GET_RNAM_PREC(self.rec.value, i))
        key = char_to_str(CSTR_STRING(NAME_RNAM(key_index)))
        cdef Obj result = GET_ELM_PREC(self.rec.value,i)
        val = make_any_gap_element(self.rec.parent(), result)
        self.i += 1
        return (key, val)


# Add support for _instancedoc_
#from sage.docs.instancedoc import instancedoc
#instancedoc(GapFunction)
#instancedoc(GapMethodProxy)
