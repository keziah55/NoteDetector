%module notedetector

%inline %{
#define SWIG_FILE_WITH_INIT

#include <sstream>

#include "onsetdetector.h"
#include "notedetector.h"

// Make SWIG happy with std::size_t and size_t being the same
typedef unsigned long int size_t;
%}


//%include "documentation.i"
//%include "python_docstrings.i"

%include "numpy.i"

//%include <std_deque.i>
%include <std_vector.i>
%include <std_except.i>
%include <std_string.i>
%include <std_map.i>
%include <typemaps.i>

%init %{
import_array();
%}

// Explicitly ignore nested classes
%ignore NoteDetector::Analyse_params;

%fragment("NumPy_Fragments");

/*! Change numpy typemap for 2D arrays so we can split a
*   2D array into two 1D arrays.
*   Used when given 2D array of frequencies and bandwidths.
*   Takes a pointer and two sizes.
*   Returns a pointer to the first array, pointer to second
*   array and length of both arrays.
*
*   The following three methods are taken directly from
*   numpy.i (Typemap suite for (DATA_TYPE* IN_ARRAY2, DIM_TYPE DIM1,
*   DIM_TYPE DIM2)) and the second one has been modified.
*/
%typecheck(SWIG_TYPECHECK_DOUBLE_ARRAY,
           fragment="NumPy_Macros")
  (parameter_t* IN_ARRAY2, DIM_TYPE DIM1, DIM_TYPE DIM2)
{
  $1 = is_array($input) || PySequence_Check($input);
}
%typemap(in,
         fragment="NumPy_Fragments")
  (parameter_t* IN_ARRAY2, DIM_TYPE DIM1, DIM_TYPE DIM2)
  (PyArrayObject* array=NULL, int is_new_object=0)
{
    npy_intp size[2] = { -1, -1 };
    array = obj_to_array_contiguous_allow_conversion($input,
      NPY_DOUBLE,
      &is_new_object);

    if (!array || !require_dimensions(array, 2) ||
      !require_size(array, size, 2)) SWIG_fail;

    std::size_t fb_size = array_size(array, 1);

    // pointer to first array
    $1 = (parameter_t*) array_data(array);
    // pointer to second array
    $2 = (parameter_t*) (array_data(array5)) + fb_size;
    // size of array
    $3 = (std::size_t) fb_size;
}
%typemap(freearg)
  (parameter_t* IN_ARRAY2, DIM_TYPE DIM1, DIM_TYPE DIM2)
{
  if (is_new_object$argnum && array$argnum)
    { Py_DECREF(array$argnum); }
}

// for some reason, all numpy integers will throw a TypeError
// because C++ doesn't understand them, so we have to
// cast these ints as ints before we can use them. Yep.
%typemap(in) int {
    $1 = static_cast<int>(PyLong_AsLong($input));
}

%typemap(in) std::size_t {
    $1 = static_cast<std::size_t>(PyLong_AsLong($input));
}

%apply (float* IN_ARRAY1, int DIM1) {(const inputSample_t* inputBuffer,
                                      const std::size_t inputBufferSize)};
// apply the typemap we created, which takes a pointer and two sizes and returns
// two pointers and one size
%apply (parameter_t* IN_ARRAY2, DIM_TYPE DIM1, DIM_TYPE DIM2) {(const parameter_t* freqs,
                                                                parameter_t* bw,
                                                                const std::size_t numDetectors)};
// %ignore operator<<;
// %include "onsetdetector.h"
// namespace std {
//     %template(OnsetList) deque<Onset>;
//     %template(FreqValues) vector<onset_freq_t>;
// }
//
// %extend Onset {
//     const std::string __repr__() {
//         std::ostringstream ss;
//         ss << *($self);
//         return ss.str();
//     }
// }


%include "onsetdetector.h"


%apply (float* IN_ARRAY1, int DIM1) {(const audioSample_t* inputBuffer,
                                      const std::size_t inputBufferSize)};
%apply (double* IN_ARRAY1, int DIM1) {(const parameter_t* freqs,
                                       const std::size_t freqsSize)};

%extend NoteDetector {
    %pythoncode %{
        SWIG__init__ = __init__
        def __init__(self, *args, **kwargs):
            if len(kwargs) != 0:
                if len(args) != 4:
                    raise TypeError('NoteDetector cannot be instantiated with a mixture of '
                                    'default positional and keyword arguments because of C++ '
                                    'binding limitations')
                optargs = NDOptArgs()
                for arg in kwargs:
                    set_method = getattr(optargs, arg, None)
                    if set_method:
                        set_method(kwargs[arg])
                    else:
                        raise TypeError('Unable to pass {0}={1} because {0} is not a valid '
                                        'paramter name'.format(arg, kwargs[arg]))
                args += (optargs,)
            NoteDetector.SWIG__init__(self, *args)
            
        ## NB this is copied directly from the DetectorBank bit of this file ##
        ## If changing anything, make sure both bits are changed ##
        def _checkBufferType(self, buf):
            # Check that the data type is float32
            # Also, flatten arrays of more than 1 dimension

            from numpy import array, dtype, mean

            # Check data type
            if buf.dtype is not dtype('float32'):
                if buf.dtype is dtype('int16') :
                    buf = array(buf, dtype=dtype('float32'))/(2**15)
                else:
                    buf = array(buf, dtype=dtype('float32'))

            # Check number of dimensions
            if buf.ndim > 1 :
                buf = mean(buf, axis=1)

            del array, dtype, mean

            return buf
    %}
};

## NB this is copied directly from the detectorbank.i ##
## If changing anything, probably want to apply changes to both ##
%pythonprepend NoteDetector::NoteDetector %{
    # make audio mono, if required
    args = list(args)
    # The c++ code only deals with mono audio but we'd like to deal with
    # more channels on demand
    # Fortunately, the input buffer is the second argument in all forms
    # of the constructor, so no need to check len(args) here.
    # This also makes sure the data type is float32
    b = self._checkBufferType(args[1])

    if b is not args[1]:
        args[1] = b
        
    # Keep a local copy so it doesn't get garbage-collected
    self._ibuf = args[1]
%}

namespace std {
    %template(vector_size_t) vector<size_t>;
    %template(OnsetDict) map<size_t, vector<size_t>>;
}


%pythoncode %{
    def _OnsetDict__str__(self):
        # manual implementation of __str__, so that it prints like a regular
        # python dictionary, rather than
        # "<detectorbank.OnsetDict; proxy of <Swig Object of type 'std::map< ]
        # size_t,std::vector< int,std::allocator< int > > > *' at 0x7f0d99c3bde0> >"
        
        out = '{'
        keys = self.keys()
        
        # if the dictionary contains stuff, print it out
        if keys:
            for k in keys[:-1]:
                out += '{}: {}, '.format(k, self.__getitem__(k), end='')
            out += '{}: {}'.format(keys[-1], self.__getitem__(keys[-1]), end='')
            
        out += '}'

        return out

    OnsetDict.__str__ = _OnsetDict__str__
%}


%include "notedetector.h"

